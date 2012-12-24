package Pompiedom::Plack::Middleware::API;
use parent 'Plack::Middleware';
use strict;

use Plack::Util::Accessor qw(db_config river);
use Pompiedom::API::Pompiedom;

sub call {
    my $self = shift;
    my $env = shift;

    my $api = Pompiedom::API::Pompiedom->new(
        hostname  => $env->{HTTP_HOST},
        db_config => $self->db_config,
        river     => $self->river,
    );

    $self->river->api($api);

    $self->river->reload_feeds;
    #$self->river->update_feeds;

    $env->{pompiedom_api} = $api;

    return $self->app->($env);
};

1;
