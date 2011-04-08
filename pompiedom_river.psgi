use 5.10.0;
use lib 'lib';
use local::lib;

use strict;
use warnings;

use Plack::Builder;
use Plack::Session::Store::File;
use Plack::Session;

use Log::Dispatch;
use Encode;
use HTML::Entities 'encode_entities_numeric';

use Pompiedom::Plack::App::River;
use Pompiedom::River::Messages;

use Date::Period::Human;
use Data::Dumper;

use YAML 'LoadFile';
use XML::OPML;

my $logger = Log::Dispatch->new(
    outputs => [
        [ 'Screen', min_level => 'debug', newline => 1 ],
    ],
    callbacks => sub { my %p = @_; return localtime() . " " . $p{message}; },
);

my $river = Pompiedom::River::Messages->new({logger => $logger});

my $app = sub {
    my $env = shift;
    my $config = eval { LoadFile('config.yml') } || {};

    my $session = Plack::Session->new($env);

    my $req = Plack::Request->new($env);
    my $res = $req->new_response(200);

    my $templ = Template->new({
        INCLUDE_PATH => ['template/custom', 'templates/default' ],
        ENCODING => 'utf8',
    });

    my $out;

    if ($req->path_info =~ m{^/$}) {
        my $ft = DateTime::Format::RFC3339->new();
        my $dp = Date::Period::Human->new({lang => 'en'});

        my @messages = $river->messages;
        for my $m (@messages) {
            $m->{datetime} = $ft->parse_datetime($m->{timestamp});
            $m->{human_readable} = ucfirst($dp->human_readable($m->{datetime}));
            $m->{description} = $m->{description};
        }

        $templ->process('pompiedom_river.tt', { 
            session => {
                username  => $session->get('username'),
                logged_in => $session->get('logged_in'),
            },
            river    => $river,
            config   => $config,
            args     => {
                link  => scalar $req->param('link'),
                title => scalar $req->param('title'),
                text  => scalar $req->param('text'),
            },
        }, \$out, {binmode => ":utf8"}) || die "$Template::ERROR\n";

        $res->content_type('text/html; charset=utf-8');
        $res->content(encode_utf8($out));
    }
    elsif ($req->path_info =~ m{^/watch$}) {
        if (!$session->get('logged_in')) {
            $res->redirect($req->script_name . '/');
            return $res->finalize;
        }
        my $feed = $req->param('feed');
        $templ->process('pompiedom_river_watch.tt', { 
                session => {
                    username => $session->get('username'),
                    logged_in => $session->get('logged_in'),
                },
                feed   => $feed,
                river  => $river,
                config => $config,
            }, \$out) || die "$Template::ERROR\n";
        $res->content_type('text/html; charset=UTF-8');
        $res->content(encode_utf8($out));
    }
    elsif ($req->path_info =~ m{^/watch/re$}) {
        if (!$session->get('logged_in')) {
            $res->redirect($req->script_name . '/');
            return $res->finalize;
        }
        $river->reload_feeds;
        $res->redirect($req->script_name . '/watch');
    }
    elsif ($req->path_info =~ m{^/watch/add$}) {
        if (!$session->get('logged_in')) {
            $res->redirect($req->script_name . '/');
            return $res->finalize;
        }
        $river->add_feed($req->param('url'), remember_feed => 1);
        $res->redirect($req->script_name . '/watch');
    }
    elsif ($req->path_info =~ m{^/watch/sub$}) {
        if (!$session->get('logged_in')) {
            $res->redirect($req->script_name . '/');
            return $res->finalize;
        }
        $river->subscribe_cloud($req->param('feed'));
        $res->redirect($req->script_name . '/watch');
    }
    elsif ($req->path_info =~ m{^/about$}) {
        $res->content_type('text/html; charset=UTF-8');
        $templ->process('about.tt', {}, \$out) || die "$Template::ERROR\n";
        $res->content(encode_utf8($out));
    }
    elsif ($req->path_info =~ m{^/session/login$}) {
        $res->content_type('text/html; charset=UTF-8');
        $templ->process('session/login.tt', {}, \$out) || die "$Template::ERROR\n";
        $res->content(encode_utf8($out));
    }
    elsif ($req->path_info =~ m{^/session/create$}) {
        my $username = $req->param('username');
        my $password = $req->param('password');
        if ($config->{users}{$username}{password} eq $password) {
            $session->set('logged_in', 1);
            $session->set('username', $username);
        }
        $res->redirect($req->script_name . '/');
    }
    elsif ($req->path_info =~ m{^/session/logout$}) {
        $session->expire;
        $res->redirect($req->script_name . '/');
    }
    elsif ($req->path_info =~ m{^/debug$}) {
        if (!$session->get('logged_in')) {
            $res->redirect($req->script_name . '/');
            return $res->finalize;
        }
        my $ft = DateTime::Format::RFC3339->new();
        my $dp = Date::Period::Human->new({lang => 'en'});

        my @messages = $river->messages;
        for my $m (@messages) {
            my $datetime = $ft->parse_datetime($m->{timestamp});
            $m->{human_readable} = ucfirst($dp->human_readable($datetime));
        }
        my $out = "<!DOCTYPE html><pre>".Dumper(\@messages);

        $res->content_type('text/html; charset=UTF-8');
        $res->content(encode_utf8($out));
    }
    elsif ($req->path_info =~ m{^/opml$}) {
        $res->content_type('text/html; charset=UTF-8');


        my $out = <<"XML";
<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
<head>
    <title>Community Reading List</title>
</head>
<body>
XML

        for my $feed (@{$river->feeds}) {
            if ($feed->{public}) {
                my $feed_name = encode_entities_numeric($feed->{name});
                my $feed_url = encode_entities_numeric($feed->{url});
                $out .= <<"XML";
    <outline text="$feed_name" htmlUrl="http://shattr.net"
    title="$feed_name" type="rss" version="RSS2" xmlUrl="$feed_url"  />
XML
            }
        }

        $out .= "</body></opml>\n";

        $res->content($out);
    }
    else {
        $res->code(404);
        $res->content('Not found');
    }
    return $res->finalize;
};

our $heart_beats = AnyEvent->timer(interval => 11, cb => sub {
    for my $c (Plack::Middleware::SocketIO::Resource->instance->connections) {
        $c->send_heartbeat if $c->is_connected;
    }
});

our $feed_update_timer = AnyEvent->timer(interval => 1*60, cb => sub {
    $logger->info("Updating feeds");
    $river->update_feeds;
});

builder {
    enable "LogDispatch", logger => $logger;
    enable "Plack::Middleware::ConditionalGET";

    enable "SocketIO", handler => sub {
        my $self = shift;

        $self->on_message(sub {
            my $self = shift;
            my ($message) = @_;
            print "Message received\n";
        });
    };

    enable "Session", store => Plack::Session::Store::File->new(
        dir => './sessions'
    );
    enable "Static", path => sub { s!^/static/!! }, root => 'static';
    mount "/rsscloud" => Pompiedom::Plack::App::River->new(river => $river)->to_app,
    mount "/"         => $app;
}

