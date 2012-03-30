# vim:ft=perl

use 5.10.0;
use lib 'lib';
use local::lib;

use strict;
use warnings;

use Plack::Builder;
use Plack::App::File;
use Plack::Session::Store::File;
use Plack::Session;

use Log::Dispatch;
use Encode;
use HTML::Entities 'encode_entities_numeric';

use Pompiedom::Plack::App::River;
use Pompiedom::Plack::App::Session;
use Pompiedom::River::Messages;

use PocketIO;

use Date::Period::Human;
use Data::Dumper;

use AnyEvent::HTTP;
use LWP::Protocol::AnyEvent::http;
use LWP::UserAgent;

use YAML 'LoadFile';

use XML::RSS;

use Plack::App::PubSubHubbub::Subscriber;
use Plack::App::PubSubHubbub::Subscriber::Config;
use Plack::App::PubSubHubbub::Subscriber::Client;

my $conf = Plack::App::PubSubHubbub::Subscriber::Config->new(
    callback      => "http://shattr.net:8086/push/callback",
    lease_seconds => 86400,
    verify        => 'sync',
);

my $push_client = Plack::App::PubSubHubbub::Subscriber::Client->new(
    config => $conf,
);

my $logger = Log::Dispatch->new(
    outputs => [
        [ 'Screen', min_level => 'debug', newline => 1 ],
    ],
    callbacks => sub { my %p = @_; return localtime() . " " . $p{message}; },
);

my $river = Pompiedom::River::Messages->new({push_client => $push_client, logger => $logger});

my $push_app = Plack::App::PubSubHubbub::Subscriber->new(
    config    => $conf,
    on_verify => sub {
        my ($topic, $token, $mode, $lease) = @_;
        $logger->info("================ on_verify");
        $logger->info("Topic: $topic");
        $logger->info("Token: $token");
        $logger->info("Mode:  $mode");
        $logger->info("Lease: $lease");
        print 'Before: ' . Dumper($river->{feeds}{$topic});
        my $ret = $river->verify_feed($topic, $token, $mode, $lease);
        print 'After:  ' . Dumper($river->{feeds}{$topic});
        return $ret;
    },
    on_ping => sub {
        my ($content_type, $content, $token) = @_;
        $logger->info("================ New content received");
        $logger->info($content);
        $river->add_feed_content($content);
        $logger->info("================ End of new content received");
    },
);
my $config = eval { LoadFile('config.yml') } || {};

my $app = sub {
    my $env = shift;

    my $session = Plack::Session->new($env);

    my $req = Plack::Request->new($env);
    my $res = $req->new_response(200);

    my $templ = Template->new({
        INCLUDE_PATH => ['template/custom', 'templates/default' ],
        ENCODING     => 'utf8',
    });

    my $out;

    if ($req->path_info =~ m{^/$}) {
        my $ft = DateTime::Format::RFC3339->new();
        my $dp = Date::Period::Human->new({lang => 'en'});

        my @messages = $river->messages;
        for my $m (@messages) {
            # FIX for twitters feeds
            if ($m->{title} && $m->{message} && ($m->{title} eq $m->{message})) {
                delete $m->{title};
            }

            $m->{datetime} = $ft->parse_datetime($m->{timestamp});
            $m->{human_readable} = ucfirst($dp->human_readable($m->{datetime}));
            #$m->{description} = $m->{description};
        }

        my $url = $req->param('link') || $req->param('url');
        $url = decode("UTF-8", $url);

        $templ->process('pompiedom_river.tt', { 
            session => {
                username  => $session->get('username'),
                logged_in => $session->get('logged_in'),
            },
            river    => $river,
            config   => $config,
            args     => {
                link  => $url,
                title => decode("UTF-8", scalar $req->param('title')),
                description  => decode("UTF-8", scalar $req->param('description')),
            },
            feeds => $env->{pompiedom_api}->UserFeeds($session->get('username')),
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
                    username  => $session->get('username'),
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
        $templ->process('about.tt', {
            session => {
                username  => $session->get('username'),
                logged_in => $session->get('logged_in'),
            },
        }, \$out) || die "$Template::ERROR\n";
        $res->content(encode_utf8($out));
    }
    elsif ($req->path_info =~ m{^/post$}) {
        if (!$session->get('logged_in')) {
            $res->redirect($req->script_name . '/');
            return $res->finalize;
        }
        
        my $feed = $req->param('feed');
        my $title = $req->param('title');
        my $link = $req->param('link');
        my $description = $req->param('description');

        $env->{pompiedom_api}->UserPostItem($feed, { title => $title,'link' => $link, description => $description });

        $env->{pompiedom_api}->PingFeed($feed);

        $res->content("OK");
    }
    elsif ($req->path_info =~ m{^/feed/(\w+)/rss.xml$}) {
        my $shortcode = $1;
        my $feed = $env->{pompiedom_api}->FeedGet($shortcode);

        $res->code(200);
        $res->content_type('application/rss+xml; charset=utf-8');
        my $rss_xml = $feed->as_string;
        $rss_xml =~ s{</description>}{</description>\n
            <cloud domain="cloud.stuifzand.eu" port="5337" path="/rsscloud/pleaseNotify" registerProcedure="" protocol="http-post" />};
        $res->content($rss_xml);
        return $res->finalize;
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
        $res->content_type('text/x-opml; charset=UTF-8');


        my $out = <<"XML";
<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
<head>
    <title>Community Reading List for shattr.net</title>
</head>
<body>
XML

        for my $feed (@{$env->{pompiedom_api}->FeedsAll}) {
            my $feed_name = encode_entities_numeric($feed->{name});
            my $feed_url = encode_entities_numeric($feed->{url});
            $out .= <<"XML";
    <outline text="$feed_name" htmlUrl="http://shattr.net"
    title="$feed_name" type="rss" version="RSS2" xmlUrl="$feed_url"  />
XML
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

#our $heart_beats = AnyEvent->timer(interval => 11, cb => sub {
#    for my $c (Plack::Middleware::SocketIO::Resource->instance->connections) {
        #$c->send_heartbeat if $c->is_connected;
#    }
#});
#
#our $heart_beats = AnyEvent->timer(interval => 11, cb => sub {
    #for my $c (@{$river->{clients}}) {
        #$c->
#
    #}
#});

our $feed_update_timer = AnyEvent->timer(interval => 1*60, cb => sub {
    $logger->info("Updating feeds");
    $river->update_feeds;
});

my $root = '/home/peter/pompiedom-river/static/socket.io';

builder {
    enable "LogDispatch", logger => $logger;
    enable "Plack::Middleware::ConditionalGET";
    enable "+Pompiedom::Plack::Middleware::API", db_config => $config->{database};

    mount "/socket.io/socket.io.js" =>
        Plack::App::File->new(file => "$root/socket.io.js");

    mount '/socket.io/static/flashsocket/WebSocketMain.swf' =>
        Plack::App::File->new(file => "$root/WebSocketMain.swf");

    mount '/socket.io/static/flashsocket/WebSocketMainInsecure.swf' =>
        Plack::App::File->new(file => "$root/WebSocketMainInsecure.swf");

    mount "/socket.io" => PocketIO->new(
        handler => sub {
            my $self = shift;
            $river->add_socket($self);
            return;
        }
    );

    mount $push_app->callback_path, $push_app;

    mount "/.well-known/host-meta" =>
        Plack::App::File->new(file => '/home/peter/pompiedom-river/static/host-meta');
    mount "/oexchange.xrd" =>
        Plack::App::File->new(file => '/home/peter/pompiedom-river/static/oexchange.xrd');

    enable "Session", store => Plack::Session::Store::File->new(
        dir => './sessions'
    );
    enable "Static", path => sub { s!^/static/!! }, root => 'static';
    mount "/rsscloud" => Pompiedom::Plack::App::River->new(river => $river)->to_app,
    mount "/session"  => Pompiedom::Plack::App::Session->new()->to_app,
    mount "/"         => $app;
}

