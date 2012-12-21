package Pompiedom::AppBase;
use strict;

use Plack::Session;
use Plack::Request;

use Template;
use Encode;

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

1;
