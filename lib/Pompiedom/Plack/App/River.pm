package Pompiedom::Plack::App::River;
use strict;
use warnings;
use parent qw/Plack::Component/;

use Plack::Util::Accessor qw(river);
use Plack::Request;
use URI;
use URI::Escape;
use XML::Feed;

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

