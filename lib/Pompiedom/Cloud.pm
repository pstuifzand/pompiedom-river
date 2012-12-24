package Pompiedom::Cloud;
use strict;
use warnings;


sub new {
    my $class = shift;
    my $args = shift;

    if (ref($args) ne 'HASH') {
        return;
    }
    my $self = {
        domain => $args->{domain},
        port => $args->{port},
        path => $args->{path},
        register_procedure => $args->{register_procedure} || $args->{registerProcedure},
        protocol => $args->{protocol},
    };

    return bless $self, $class;
}

sub domain {
    my $self = shift;
    return $self->{domain};
}

sub port {
    my $self = shift;
    return $self->{port};
}

sub path {
    my $self = shift;
    return $self->{path};
}

sub register_procedure {
    my $self = shift;
    return $self->{register_procedure};
}

sub protocol {
    my $self = shift;
    return $self->{protocol};
}

1;

