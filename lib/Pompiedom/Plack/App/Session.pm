package Pompiedom::Plack::App::Session;
use strict;
use warnings;

use parent 'Plack::Component';


use Plack::Request;
use Plack::Session;
use URI;
use URI::Escape;
use XML::Feed;
use Encode;

sub call {
    my $self = shift;
    my $env = shift;

    my $req = Plack::Request->new($env);
    my $res = $req->new_response(200);

    my $session = Plack::Session->new($env);

    my $templ = Template->new({
        INCLUDE_PATH => ['template/custom', 'templates/default' ],
        ENCODING     => 'utf8',
    });

    my $out;
    if ($req->path_info =~ m{^/login$}) {
        $res->content_type('text/html; charset=UTF-8');
        $templ->process('session/login.tt', {}, \$out) || die "$Template::ERROR\n";
        $res->content(encode_utf8($out));
    }
    elsif ($req->path_info =~ m{^/create$}) {
        my $username = $req->param('username');
        my $password = $req->param('password');

        if ($env->{pompiedom_api}->UserCanLogin($username, $password)) {
            $session->set('logged_in', 1);
            $session->set('username', $username);
            $res->redirect('/');
            return $res->finalize;
        }

        $res->redirect($req->script_name . '/login');
    }
    elsif ($req->path_info =~ m{^/logout$}) {
        $session->expire;
        $res->redirect('/');
    }
    else {
        return $req->new_response(404, [], 'Not found')->finalize;
    }

    return $res->finalize;
}

1;
