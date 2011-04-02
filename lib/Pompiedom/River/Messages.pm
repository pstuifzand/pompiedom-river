package Pompiedom::River::Messages;
use strict;
use warnings;
use YAML 'LoadFile', 'DumpFile';
use XML::Feed;
use AnyEvent::HTTP;
use Date::Period::Human;
use DateTime::Format::RFC3339;
use Plack::Middleware::SocketIO::Resource;
use Template;
use HTML::Scrubber;
use URI::Escape;
use Data::Dumper;

sub new {
    my $klass = shift;
    my $self = { messages => [], ids => {} };
    $self = bless $self, $klass; 
    $self->reload_feeds;
    return $self;
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
    return [ values %{$self->{feeds}} ];
}

sub save_feeds {
    my ($self) = @_;
    DumpFile('pompiedom-river-feeds.yml', $self->feeds);
}

sub reload_feeds {
    my $self = shift;
    my $indata = eval { LoadFile('pompiedom-river-feeds.yml') } || [];

    for (@$indata) {
        $self->add_feed_internal($_);
    }
    return;
}

sub add_feed_internal {
    my ($self, $info) = @_;
    $self->{feeds}{$info->{url}} = $info;
    return;
}

sub subscribe_cloud {
    my ($self, $url) = @_;

    my $sub = $self->{feeds}{$url};

    my $subscribe_uri = URI->new('http://'.$sub->{cloud}{domain}.':'.$sub->{cloud}{port}.$sub->{cloud}{path});

    my $body = "notifyProcedure=&port=5000&path=".uri_escape('/rsscloud/notify')."&protocol=". uri_escape('http-post') ."&url1=".uri_escape($url);

    http_post($subscribe_uri->as_string, $body,
        headers => {
            'content-type' => 'application/x-www-form-urlencoded'
            'user-agent' => 'Pompiedom-River/'. $Pompiedom::Plack::App::River::VERSION . ' (rssCloud)'
        }, sub {
        print $_[0] . "\n";
        print Dumper($_[1]);

        $self->{feeds}{$url}{subscribed} = time();
    });

    return;
}

sub create_scrubber {
    my $self = shift;
    my $scrubber = HTML::Scrubber->new(allow => [ qw[ p b i u hr br em strong pre code tt kbd blockquote q ] ]);
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

sub add_feed {
    my ($self, $url, %options) = @_;

    my $uri = URI->new($url);

    http_get($url,
        headers => {
            'User-Agent' => 'Pompiedom-River/'. $Pompiedom::Plack::App::River::VERSION . ' (rssCloud)'
        }, sub {
            my ($data, $headers) = @_;

            my $new_subscription = {
                url => $url,
            };

            if ($headers->{Status} =~ m{200}) {
                $new_subscription->{status} = 'ok';
            }
            else {
                $new_subscription->{status} = 'error';
            }

            my $feed = XML::Feed->parse(\$data);
            if (!$feed) {
                warn "Can't parse feed";
                return;
            }
            $new_subscription->{name}  = $feed->title;
            $new_subscription->{cloud} = $feed->{rss}->channel('cloud');

            my $ft       = DateTime::Format::RFC3339->new();
            my $scrubber = $self->create_scrubber();
            
            for my $entry (reverse $feed->entries) {
                # Skip to next message if seen
                next if $self->has_message($entry->id);

                print "Feed $url " . $entry->id . " added\n";

                # Change time to localtime
                my $datetime = $entry->issued;
                $datetime->set_time_zone('Europe/Amsterdam');

                # Create a message based on entry
                my $message = {
                    title     => ($entry->title) || '',
                    base      => ($entry->base),
                    link      => ($entry->link) || '',
                    message   => $entry->content->body ? $scrubber->scrub($entry->content->body) : '',
                    id        => ($entry->id),
                    author    => (scalar ($feed->author || $uri->host)),
                    timestamp => $ft->format_datetime($datetime),
                    feed      => {
                        title => ($feed->title),
                        link  => ($feed->link),
                    },
                };
                # Delete links that aren't http.
                delete $message->{link} unless $message->{link} =~ m/^http:/;

                # Get enclosure info
                if ($entry->enclosure) {
                    $message->{enclosure} = {
                        type   => ($entry->enclosure->type),
                        url    => ($entry->enclosure->url),
                        length => ($entry->enclosure->length),
                    };
                }
                # Add message to the internal river
                $self->add_message($message);

                # Human readable date information
                my $dp = Date::Period::Human->new({lang => 'en'});
                $message->{human_readable} = ucfirst($dp->human_readable($datetime));

                # Format message for river in HTML
                my $templ = Template->new({
                    INCLUDE_PATH => '.',
                });
                my $html;
                $templ->process('pompiedom_river_message.tt', { 
                    message => $message,
                }, \$html) || die "$Template::ERROR\n";

                # Send the message to all connected rivers
                for my $conn (Plack::Middleware::SocketIO::Resource->instance->connections) {
                    if ($conn->is_connected) {
                        $conn->send_message({ id => $message->{id}, html => $html }); 
                    }
                }

            }

            if ($options{remember_feed}) {
                # If this works, save the feed
                $self->add_feed_internal($new_subscription);
                $self->save_feeds;
            }
        });
}

1;

