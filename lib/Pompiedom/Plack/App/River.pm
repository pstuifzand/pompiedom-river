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
    $self->river->add_feed($url);
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

