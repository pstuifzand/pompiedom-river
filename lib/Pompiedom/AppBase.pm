package Pompiedom::AppBase;
use strict;
use parent 'Plack::Component';

use Data::Dumper;
use Plack::Session;
use Plack::Request;

use Template;
use Encode;

sub prepare_app {
    my $self = shift;

    $self->{handlers} = {
        GET  => [],
        POST => [],
    };

    $self->init_handlers();

    # Sort handlers
    for my $method (keys %{$self->{handlers}}) {
        @{$self->{handlers}{$method}} = sort {length($b->[0]) <=> length($a->[0]) } @{$self->{handlers}{$method}};
    }

    return;
}

sub register_handler {
    my ($self, $method, $prefix, $handler) = @_;
    push @{$self->{handlers}{$method}}, Pompiedom::AppBase::HandlerFunc->new($prefix, $handler);
    return;
}

sub call {
    my ($self, $env) = @_;

    my $req = Plack::Request->new($env);

    my $handler;
    my @args = ();
    for my $h (@{$self->{handlers}{$req->method}}) {
        my $prefix = $h->[0];
        if (ref($prefix) eq 'Regexp') {
            print "Trying to match prefix\n";
            if (@args = $req->path_info =~ m/^$prefix/) {
                $handler = $h->[1];
                last;
            }
            next;
        }
        elsif ($req->path_info =~ m/^$prefix$/) {
            $handler = $h->[1];
            last;
        }
    }
    if ($handler) {
        return $handler->($self, $env, \@args);
    }
    return $req->new_response(404, [], 'Not found')->finalize;
}

sub template {
    my $self = shift;

    $self->{template} ||= Template->new({
        INCLUDE_PATH => ['template/custom', 'templates/default' ],
        ENCODING     => 'utf8',
    });

    return $self->{template};
}

sub render_template {
    my ($self, $name, $args, $env) = @_;
    my $out;

    my $req = Plack::Request->new($env);
    my $session = Plack::Session->new($env);

    $args->{session} = {
        username  => $session->get('username'),
        logged_in => $session->get('logged_in'),
    };

    my $res = $req->new_response(200);

    $self->template->process($name, $args, \$out, {binmode => ":utf8"}) || die "$Template::ERROR\n";

    $res->content_type('text/html; charset=utf-8');
    $res->content(encode_utf8($out));

    return $res->finalize;
}

package Pompiedom::AppBase::HandlerFunc;

sub new {
    my ($klass, $prefix, $handler) = @_;
    return bless [$prefix,$handler], $klass;
}

1;
