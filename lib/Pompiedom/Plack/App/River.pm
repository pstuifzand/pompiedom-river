package Pompiedom::Plack::App::River;
use strict;
use warnings;
use parent qw/Plack::Component/;

our $VERSION = '0.2';

use Plack::Util::Accessor qw(river);

use Data::Dumper;
use Plack::Request;
use URI;

use AnyEvent::Handle;
use AnyEvent::HTTP;

use URI::Escape;
use DateTime::Format::RFC3339;
use Date::Period::Human;
use XML::Feed;
use Template;
use Encode;

sub notify {
    my ($self, $env, $req) = @_;

    my $body = $req->raw_body;
    my ($url) = ($body =~ m/^url=(.+)$/);
    $url = uri_unescape($url);
    my $uri = URI->new($url);

    http_get($url,
        headers => {
            'User-Agent' => 'Pompiedom-River/'. $VERSION . ' (rssCloud)'
        }, sub {
            my ($data, $headers) = @_;

            my $feed = XML::Feed->parse(\$data);
            if (!$feed) {
                warn "Can't parse feed";
                return;
            }

            my $ft = DateTime::Format::RFC3339->new();

            for my $entry (reverse $feed->entries) {
                next if $self->river->has_message($entry->id);

                print "Feed $url " . $entry->id . " added\n";

                my $datetime = $entry->issued;
                $datetime->set_time_zone('Europe/Amsterdam');

                my $message = {
                    title     => ($entry->title) || '',
                    base      => ($entry->base),
                    link      => ($entry->link) || '',
                    message   => ($entry->content->body) || '',
                    id        => ($entry->id),
                    author    => (scalar ($feed->author || $uri->host)),
                    timestamp => $ft->format_datetime($datetime),
                    feed      => {
                        title => ($feed->title),
                        link  => ($feed->link),
                    },
                };
                delete $message->{link} unless $message->{link} =~ m/^http:/;

                if ($entry->enclosure) {
                    $message->{enclosure} = {
                        type   => ($entry->enclosure->type),
                        url    => ($entry->enclosure->url),
                        length => ($entry->enclosure->length),
                    };
                }
                $self->river->add_message($message);

                my $dp = Date::Period::Human->new({lang => 'en'});
                $message->{human_readable} = ucfirst($dp->human_readable($datetime));

                my $templ = Template->new({
                    INCLUDE_PATH => '.',
                });

                my $html;
                $templ->process('pompiedom_river_message.tt', { 
                    message => $message,
                }, \$html) || die "$Template::ERROR\n";

                for my $conn (Plack::Middleware::SocketIO::Resource->instance->connections) {
                    if ($conn->is_connected) {
                        $conn->send_message({ id => $message->{id}, html => $html }); 
                    }
                }
            }
        });
    return $req->new_response(200, [], "Rocks!")->finalize;
}

sub call {
    my $self = shift;
    my $env = shift;

    my $req = Plack::Request->new($env);

    if ($req->path_info =~ m{^/notify}) {
        $self->notify($env, $req);
    }

    $req->new_response(404, [], 'Not found')->finalize;
}

1;

