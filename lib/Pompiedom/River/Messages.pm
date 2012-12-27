# Copyright (c) 2010-2013 Peter Stuifzand
# Copyright (c) 2010-2013 Other contributors as noted in the AUTHORS file
# 
# This file is part of Pompiedom.
# 
# Pompiedom is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
# 
# Pompiedom is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

package Pompiedom::River::Messages;
use strict;
use warnings;
use YAML 'LoadFile', 'DumpFile';
use XML::Feed;
use AnyEvent::HTTP;
use Date::Period::Human;
use DateTime;
use DateTime::Duration;
use DateTime::Format::RFC3339;
use Template;
use URI::Escape;
use Data::Dumper;
use Encode 'encode', 'decode';
use Coro 'async';

use PocketIO::Sockets;
use Plack::Util::Accessor qw(river api);

use Pompiedom::Scrubber;
use Pompiedom::Feed;
use Pompiedom::Cloud;

use XML::Atom;

$XML::Atom::ForceUnicode = 1;

our $VERSION = '0.2';

sub new {
    my $klass = shift;
    my $args = shift;

    my $self = { messages => [], ids => {} };
    $self = bless $self, $klass; 
    #$self->reload_feeds;
    $self->{logger} = $args->{logger};
    $self->{push_client} = $args->{push_client};

    $self->{user_agent} = 'Pompiedom-River/' . $VERSION . ' (http://github.com/pstuifzand/pompiedom-river)';
    return $self;
}

sub logger {
    my $self = shift;
    return $self->{logger};
}

sub add_message {
    my ($self, $message) = @_;
    $self->{ids}{$message->{id}} = 1;
    push @{$self->{messages}}, $message;
}

sub has_message {
    my ($self, $id) = @_;
    return $self->{ids}{$id};
}

sub messages {
    my $self = shift;
    return sort{ $b->{timestamp} cmp $a->{timestamp} } @{$self->{messages}};
}

sub messages_for_user {
    my $self = shift;
    my $username = shift;
    my %feeds;

    print "Getting messages for $username\n";
    for ($self->api->GetUserFeeds($username)) {
        $feeds{$_->url} = 1;
    }
    return grep { $feeds{ $_->{feed}{self_link} } } $self->messages;
}

sub feeds {
    my $self = shift;
    return sort { lc $a->name cmp lc $b->name } values %{$self->{feeds}};
}

sub save_feeds {
    my ($self) = @_;

    #DumpFile('pompiedom-river-feeds.yml', [$self->feeds]);

    #for my $feed ($self->feeds) {
    #    $self->api->SaveFeed($feed);
    #}

    return;
}

sub reload_feeds {
    my $self = shift;

    my @feeds = $self->api->GetAllExtFeeds();

    for my $feed (@feeds) {
        next if $feed->mode eq 'unsubscribe';
        $self->add_feed_internal($feed);
    }

    return;
}

sub unsubscribe_feed {
    my ($self, $topic) = @_;
    delete $self->{feeds}{$topic};
    return 1;
}

sub resubscribe_feed {
    my ($self, $topic) = @_;
    if (!exists $self->{feeds}{$topic}) {
        return;
    }
    $self->{feeds}{$topic}->subscribed(DateTime->now);
    return 1;
}

sub verify_feed {
    my ($self, $topic, $token, $mode, $lease) = @_;

    if ($token && $self->{feeds}{$topic}->token 
        && $token ne $self->{feeds}{$topic}->token) {
        return 0;
    }

    if ($self->{feeds}{$topic}->mode ne $mode) {
        return 0;
    }

    if ($mode eq 'subscribe') {
        if (!$self->resubscribe_feed($topic)) {
            return 0;
        }
    }
    elsif ($mode eq 'unsubscribe') {
        if (!$self->unsubscribe_feed($topic)) {
            return 0;
        }
    }

    $self->api->SaveFeed($self->{feeds}{$topic});

    #$self->save_feeds;

    return 1;
}

sub update_feeds {
    my $self = shift;

    $self->logger->info("Updating feeds");

    for my $feed ($self->feeds) {
        if ($feed->subscribed && ($feed->cloud || $feed->hub)) {
            if (DateTime::Duration->compare(DateTime->now() - $feed->subscribed, DateTime::Duration->new(hours => 24)) < 0) {
                $self->logger->info("Not updating (subscribed): " . $feed->url);
                next;
            }
            $self->logger->info("Resubscribing: " . $feed->url);
            $self->subscribe_cloud($feed->url);
            next;
        }
        elsif (DateTime::Duration->compare(DateTime->now() - $feed->updated, DateTime::Duration->new(minutes => 10)) < 0) {
            $self->logger->info("Not updating (time): " . $feed->url);
            next;
        }
        else {
            $self->logger->info("Updating: " . $feed->url);
            $self->add_feed($feed->url, remember_feed => 1);
        }
    }

    return;
}

sub add_feed_internal {
    my ($self, $info) = @_;

    if (!$info->url) {
        return;
    }

    #if (!$info->cloud) {
    #    delete $info->cloud;
    #}

    $self->{feeds}{$info->url} = $info;
    return;
}

sub _subscribe_hub {
    my ($self, $feed) = @_;
    $self->logger->info("_subscribe_hub " . $feed->url);

    return unless $feed->hub;

    $self->logger->info("Subscribing to " . $feed->url . ' at ' . $feed->hub);
    async {
        my $token = 'token';

        $self->{feeds}{$feed->url}->token($token);
        $self->{feeds}{$feed->url}->mode('subscribe');

        my $resp = $self->{push_client}->subscribe($feed->{hub}, $feed->url, $token);
        if ($resp->{success} eq 'verified') {
            $self->{feeds}{$feed->url}->subscribed(DateTime->now());
            $self->{feeds}{$feed->url}->token($token);
            # $self->save_feeds;
            $self->api->SaveFeed($self->{feeds}{$feed->url});
        }
    };
}

sub _subscribe_cloud {
    my ($self, $sub) = @_;

    return unless $sub->cloud;
    return unless $sub->cloud->domain;
    return unless $sub->cloud->port;
    return unless $sub->cloud->path;

    $self->logger->info("_subscribe_cloud " . $sub->url);

    my $url = $sub->url;

    my $subscribe_uri = URI->new('http://'.$sub->cloud->domain . ':' . $sub->cloud->port.$sub->cloud->path);

    my $body = "notifyProcedure=&port=8086&path=".uri_escape('/rsscloud/notify')."&protocol=". uri_escape('http-post') ."&url1=".uri_escape($url);

    http_post($subscribe_uri->as_string, $body,
        headers => {
            'content-type' => 'application/x-www-form-urlencoded',
            'user-agent'   => $self->{user_agent},
        }, sub {
            if ($_[1]->{Status} == 200 && $_[0] =~ m/success="true"/) {
                $self->{feeds}{$url}->subscribed(DateTime->now);
                $self->api->SaveFeed($self->{feeds}{$url});
                #$self->save_feeds;
            }
            else {
                $self->{feeds}{$url}->subscribed(DateTime->now);
                $self->api->SaveFeed($self->{feeds}{$url});
                #$self->save_feeds;
            }
        });

    return;
}

sub subscribe_cloud {
    my ($self, $url) = @_;

    my $sub = $self->{feeds}{$url};

    if ($sub) {
        if ($sub->hub) {
            $self->_subscribe_hub($sub);
        }
        elsif ($sub->cloud) {
            $self->_subscribe_cloud($sub);
        }
    }
}

sub create_scrubber {
    my $self = shift;
    return Pompiedom::Scrubber->new();
}


sub add_feed_content {
    my ($self, $data, $url) = @_;

    my $feed = XML::Feed->parse(\$data);
    if (!$feed) {
        die "Can't parse feed: $data";
    }

    my $ft       = DateTime::Format::RFC3339->new();
    my $scrubber = $self->create_scrubber();

    my $templ = Template->new({
        INCLUDE_PATH => ['template/custom', 'templates/default' ],
        ENCODING => 'utf8',
    });

    my @to_send;
    
    for my $entry (reverse $feed->entries) {
        # Skip to next message if seen
        next if $self->has_message($entry->id);

        # Change time to localtime
        my $datetime = $entry->issued || $entry->modified;
        if ($datetime) {
            $datetime->set_time_zone('Europe/Amsterdam');
        }

        my $d = sub {return $_[0];};

        # Create a message based on entry
        my $message = {
            title     => $d->($entry->title) || '',
            base      => $d->($entry->base),
            link      => $d->($entry->link) || '',
            id        => $d->($entry->id),
            author    => $d->((scalar ($feed->author))),
            timestamp => $datetime ? $ft->format_datetime($datetime) : undef,
            feed      => {
                title => $d->($feed->title),
                link  => $d->($feed->link),
                self_link => $d->($feed->self_link || $url),
            },
        };
        if ($datetime) {
            $message->{unix_timestamp} = $datetime->epoch();
        }
        else {
            $message->{unix_timestamp} = 1;
        }

        if ($entry->content->body) {
            $message->{description} = $scrubber->scrub($d->($entry->content->body));
        }
        else {
            $message->{description} = '';
        }

        $message->{feed}{image} = $feed->{rss}->image('url') if $feed->{rss};

        # Delete links that aren't http.
        delete $message->{link} unless $message->{link} =~ m/^http:/;

        # Get enclosure info
        if ($entry->enclosure) {
            $message->{enclosure} = {
                type   => $d->($entry->enclosure->type),
                url    => $d->($entry->enclosure->url),
                length => $d->($entry->enclosure->length),
            };
        }

        if ($message->{title}) {
            $message->{description} = $message->{title};
            delete $message->{title};
        }

        # Add message to the internal river
        $self->add_message($message);

        # Human readable date information
        my $dp = Date::Period::Human->new({lang => 'en'});
        if ($datetime) {
            $message->{human_readable} = ucfirst($dp->human_readable($datetime));
        }

        # Format message for river in HTML
        my $html;
        $templ->process('pompiedom_river_message.tt', { 
            message => $message,
        }, \$html, {binmode => ":utf8"}) || die "$Template::ERROR\n";

        next if $self->api->{db}->HaveFeedItemSeen($message->{id});

        push @to_send, { id => $message->{id}, html => $html };
    }

    my @users = $self->api->GetUsernamesForFeed($url);

    if ($self->sockets) {
        for my $item (@to_send) {
            for my $username (@users) {
                $self->sockets->in($username)->send($item);
            }
        }
    }

    return $feed;
}
sub sockets {
    my $self = shift;
    return $self->{sockets};
}

sub connect_pool {
    my ($self, $socket) = @_;
    $self->{sockets} = $socket->sockets;
    return;
}

sub remove_feed {
    my ($self, $url) = @_;
    $self->{feeds}{$url}->mode('unsubscribe');
    $self->{feeds}{$url}{status} = 'unsubscribe';
    $self->api->SaveFeed($self->{feeds}{$url});
    #$self->save_feeds;
    return;
}

sub add_feed {
    my ($self, $url, %options) = @_;

    my $uri = URI->new($url);

    http_get($url,
        headers => {
            'User-Agent' => $self->{user_agent},
        }, sub {
            my ($data, $headers) = @_;

            my $new_subscription = $self->{feeds}{$url} || Pompiedom::Feed->new({
                url => $url,
                updated => DateTime->now(),
            });

            if ($headers->{Status} =~ m{200}) {
                $new_subscription->status('ok');
            }
            else {
                $new_subscription->status('error');
            }

            my $feed = eval { $self->add_feed_content($data, $url) };
            if ($@) {
                warn "Can't add feed ${url} $@";
                return;
            }

            if ($feed) {
                $new_subscription->name($feed->title);
                if ($feed->{rss}) {
                    my $cloud = $feed->{rss}->channel('cloud');
                    $new_subscription->cloud(Pompiedom::Cloud->new($cloud));
                }

                # Don't know how to get the Hub from RSS feeds
                if ($feed->{atom}) {
                    my $elem = (grep { $_->rel eq 'hub' } $feed->{atom}->link)[0];
                    if ($elem) {
                        $new_subscription->hub($elem->href);
                    }
                }

                if ($options{remember_feed} && !$self->{feeds}{$url}) {
                    # If this works, save the feed
                    $self->add_feed_internal($new_subscription);
                    $self->api->SaveFeed($new_subscription);
                }

                if ($options{callback}) {
                    $options{callback}->();
                }

            }
        });
}

1;

