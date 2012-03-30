package Pompiedom::River::Messages;
use strict;
use warnings;
use YAML 'LoadFile', 'DumpFile';
use XML::Feed;
use AnyEvent::HTTP;
use Date::Period::Human;
use DateTime::Format::RFC3339;
use Template;
use HTML::Scrubber;
use URI::Escape;
use Data::Dumper;
use Encode 'encode', 'decode';
use Coro 'async';

use XML::Atom;
$XML::Atom::ForceUnicode = 1;

our $VERSION = '0.2';

sub new {
    my $klass = shift;
    my $args = shift;

    my $self = { messages => [], ids => {} };
    $self = bless $self, $klass; 
    $self->reload_feeds;
    $self->{logger} = $args->{logger};
    $self->{push_client} = $args->{push_client};
    $self->{clients} = [];

    $self->{user_agent} = 'Pompiedom-River/' . $VERSION . ' (http://github.com/pstuifzand/pompiedom-river)';
    return $self;
}

sub add_socket {
    my ($self, $client) = @_;
    push @{$self->{clients}}, $client;
    return;
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

sub feeds {
    my $self = shift;
    return [ sort { lc $a->{name} cmp lc $b->{name}} values %{$self->{feeds}} ];
}

sub save_feeds {
    my ($self) = @_;
    DumpFile('pompiedom-river-feeds.yml', $self->feeds);
    return;
}

sub reload_feeds {
    my $self = shift;
    my $indata = eval { LoadFile('pompiedom-river-feeds.yml') } || [];

    for (@$indata) {
        next if $_->{mode} eq 'unsubscribe';
        $self->add_feed_internal($_);
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

    $self->{feeds}{$topic}{subscribed} = time();
    return 1;
}

sub verify_feed {
    my ($self, $topic, $token, $mode, $lease) = @_;

    if ($token && $self->{feeds}{$topic}{token} 
        && $token ne $self->{feeds}{$topic}{token}) {
        return 0;
    }

    if ($self->{feeds}{$topic}{mode} ne $mode) {
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

    $self->save_feeds;

    return 1;
}

sub update_feeds {
    my $self = shift;

    for my $feed (@{$self->feeds}) {
        if ($feed->{subscribed} && ($feed->{cloud} || $feed->{hub})) {
            if (time() - $feed->{subscribed} < 24*60*60) {
                $self->logger->info("Not updating (subscribed): " . $feed->{url});
                next;
            }
            $self->logger->info("Resubscribing: " . $feed->{url});
            $self->subscribe_cloud($feed->{url});
            next;
        }
        elsif (time() - $feed->{updated} < 30 * 60) {
            $self->logger->info("Not updating (time): " . $feed->{url});
            next;
        }
        else {
            $self->logger->info("Updating: " . $feed->{url});
            $self->add_feed($feed->{url});
        }
    }

    return;
}

sub add_feed_internal {
    my ($self, $info) = @_;
    if (!$info->{url}) {
        return;
    }
    if (!$info->{cloud}) {
        delete $info->{cloud};
    }
    $self->{feeds}{$info->{url}} = $info;
    return;
}

sub _subscribe_hub {
    my ($self, $feed) = @_;
    return unless $feed->{hub};

    $self->logger->info("Subscribing to " . $feed->{url} . ' at ' . $feed->{hub});
    async {
        my $token = 'token';

        $self->{feeds}{$feed->{url}}{token} = $token;
        $self->{feeds}{$feed->{url}}{mode} = 'subscribe';

        my $resp = $self->{push_client}->subscribe($feed->{hub}, $feed->{url}, $token);
        if ($resp->{success} eq 'verified') {
            $self->{feeds}{$feed->{url}}{subscribed} = time();
            $self->{feeds}{$feed->{url}}{token} = $token;
            $self->save_feeds;
        }
    };
}

sub _subscribe_cloud {
    my ($self, $sub) = @_;
    return unless $sub->{cloud};
    my $url = $sub->{url};

    my $subscribe_uri = URI->new('http://'.$sub->{cloud}{domain}.':'.$sub->{cloud}{port}.$sub->{cloud}{path});

    my $body = "notifyProcedure=&port=8086&path=".uri_escape('/rsscloud/notify')."&protocol=". uri_escape('http-post') ."&url1=".uri_escape($url);

    http_post($subscribe_uri->as_string, $body,
        headers => {
            'content-type' => 'application/x-www-form-urlencoded',
            'user-agent'   => $self->{user_agent},
        }, sub {
            if ($_[1]->{Status} == 200 && $_[0] =~ m/success="true"/) {
                $self->{feeds}{$url}{subscribed} = time();
                $self->save_feeds;
            }
            else {
                print Dumper(\@_);
                $self->{feeds}{$url}{subscribed} = time();
                $self->save_feeds;
            }
        });

    return;
}

sub subscribe_cloud {
    my ($self, $url) = @_;

    my $sub = $self->{feeds}{$url};

    if ($sub->{hub}) {
        $self->_subscribe_hub($sub);
    }
    elsif ($sub->{cloud}) {
        $self->_subscribe_cloud($sub);
    }
}

sub create_scrubber {
    my $self = shift;
    my $scrubber = HTML::Scrubber->new(allow => [ qw[ ul ol li p b i u hr br em strong pre code tt kbd blockquote q ] ]);
    $scrubber->rules(
        img => {
            src => 1,
            alt => 1,                 # alt attribute allowed
            width => 1,
            height => 1,
            'style' => 1,
            '*' => 0,                 # deny all other attributes
        },
        a => {
            href => 1,
            alt  => 1,
            title => 1,
            'style' => 1,
            '*' => 0,
        },
    );

    return $scrubber;
}

sub add_feed_content {
    my ($self, $data) = @_;

    my $feed = XML::Feed->parse(\$data);
    if (!$feed) {
        warn "Can't parse feed: $data";
        return;
    }

    my $ft       = DateTime::Format::RFC3339->new();
    my $scrubber = $self->create_scrubber();

    my $templ = Template->new({
        INCLUDE_PATH => ['template/custom', 'templates/default' ],
        ENCODING => 'utf8',
    });
    
    for my $entry (reverse $feed->entries) {
        # Skip to next message if seen
        next if $self->has_message($entry->id);

        #print "Feed $url " . $entry->title . " added\n";

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
            timestamp => $ft->format_datetime($datetime),
            feed      => {
                title => $d->($feed->title),
                link  => $d->($feed->link),
            },
        };
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

        if ($message->{title} eq $message->{description}) {
            delete $message->{title};
        }
        # Add message to the internal river
        $self->add_message($message);

        # Human readable date information
        my $dp = Date::Period::Human->new({lang => 'en'});
        $message->{human_readable} = ucfirst($dp->human_readable($datetime));

        # Format message for river in HTML
        my $html;
        $templ->process('pompiedom_river_message.tt', { 
            message => $message,
        }, \$html, {binmode => ":utf8"}) || die "$Template::ERROR\n";

        for my $c (@{$self->{clients}}) {
            $c->send({id => $message->{id}, html => $html});
        }
    }
    return $feed;
}

sub remove_feed {
    my ($self, $url) = @_;
    $self->{feeds}{$url}{mode} = 'unsubscribe';
    $self->{feeds}{$url}{status} = 'unsubscribe';
    return;
}

sub add_feed {
    my ($self, $url, %options) = @_;

    my $uri = URI->new($url);

    if ($self->{feeds}{$url}) {
        $self->{feeds}{$url}{updated} = time();
    }

    http_get($url,
        headers => {
            'User-Agent' => $self->{user_agent},
        }, sub {
            my ($data, $headers) = @_;

            my $new_subscription = $self->{feeds}{$url} || {
                url => $url,
            };

            if ($headers->{Status} =~ m{200}) {
                $new_subscription->{status} = 'ok';
            }
            else {
                $new_subscription->{status} = 'error';
            }

            my $feed = $self->add_feed_content($data);

            if ($feed) {
                $new_subscription->{name}  = $feed->title;
                $new_subscription->{cloud} = $feed->{rss}->channel('cloud') if $feed->{rss};

                # Don't know how to get the Hub from RSS feeds
                if ($feed->{atom}) {
                    my $elem = (grep { $_->rel eq 'hub' } $feed->{atom}->link)[0];
                    if ($elem) {
                        $new_subscription->{hub} = $elem->href;
                    }
                }
            }
    
            if ($options{remember_feed} && !$self->{feeds}{$url}) {
                # If this works, save the feed
                $self->add_feed_internal($new_subscription);
            }

            $self->save_feeds;
        });
}

1;

