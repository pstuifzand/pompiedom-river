package Pompiedom::Plack::App::Subscription;
use strict;
use warnings;

use parent 'Plack::Component';

use Plack::Util::Accessor 'config', 'river';

use Plack::Request;
use Plack::Session;
use URI;
use URI::Escape;
use XML::Feed;
use Encode;
use HTML::Entities 'encode_entities_numeric';
use Template;

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
    if ($req->path_info =~ m{^$}) {
        if (!$session->get('logged_in')) {
            $res->redirect($req->script_name . '/');
            return $res->finalize;
        }
        my $feed = $req->param('feed');
        $templ->process('pompiedom_river_watch.tt', { 
                session => {
                    username  => $session->get('username'),
                    logged_in => $session->get('logged_in'),
                },
                feed   => $feed,
                river  => $self->river,
                config => $self->config,
            }, \$out) || die "$Template::ERROR\n";
        $res->content_type('text/html; charset=UTF-8');
        $res->content(encode_utf8($out));
    }
    elsif ($req->path_info =~ m{^/re$}) {
        if (!$session->get('logged_in')) {
            $res->redirect($req->script_name);
            return $res->finalize;
        }
        $self->river->reload_feeds;
        $res->redirect($req->script_name);
    }
    elsif ($req->path_info =~ m{^/add$}) {
        if (!$session->get('logged_in')) {
            $res->redirect($req->script_name);
            return $res->finalize;
        }
        $self->river->add_feed($req->param('url'), remember_feed => 1);
        $res->redirect($req->script_name);
    }
    elsif ($req->path_info =~ m{^/sub$}) {
        if (!$session->get('logged_in')) {
            $res->redirect($req->script_name . '/');
            return $res->finalize;
        }
        $self->river->subscribe_cloud($req->param('feed'));
        $res->redirect($req->script_name);
    }
    elsif ($req->path_info =~ m{^/unsub$}) {
        if (!$session->get('logged_in')) {
            $res->redirect($req->script_name . '/');
            return $res->finalize;
        }
        $self->river->remove_feed($req->param('feed'));
        $res->redirect($req->script_name);
    }
    else {
        return $req->new_response(404, [], 'Not found')->finalize;
    }

    return $res->finalize;
}

1;

