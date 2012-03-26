package Pompiedom::Plack::Middleware::API;
use parent 'Plack::Middleware';
use strict;

use Plack::Util::Accessor qw(db_config);
use Pompiedom::API::Pompiedom;

sub call {
    my $self = shift;
    my $env = shift;

    my $api = Pompiedom::API::Pompiedom->new(
        hostname  => $env->{HTTP_HOST},
        db_config => $self->db_config,
    );

    $env->{pompiedom_api} = $api;

    return $self->app->($env);
};

1;
