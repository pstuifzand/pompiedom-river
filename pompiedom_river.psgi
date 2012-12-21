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

use Pompiedom::Plack::App::RSSCloud;
use Pompiedom::Plack::App::Feed;
use Pompiedom::Plack::App::Subscription;
use Pompiedom::Plack::App::Session;
use Pompiedom::Plack::App::OPML;
use Pompiedom::Plack::App::River;

use Pompiedom::River::Messages;

use PocketIO;

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
#        [ 'Screen', min_level => 'debug', newline => 1 ],
        [ 'File',   min_level => 'debug', newline => 1, filename => 'logs/pompiedom.log' ],
    ],
    callbacks => sub { my %p = @_; return localtime() . " " . $p{message}; },
);

my $river = Pompiedom::River::Messages->new({push_client => $push_client, logger => $logger});

my $push_app = Plack::App::PubSubHubbub::Subscriber->new(
    config    => $conf,
    on_verify => sub {
        my ($topic, $token, $mode, $lease) = @_;
        $logger->info("Verify feed: Topic: $topic, Token: $token, Mode:  $mode, Lease: $lease");
        my $ret = $river->verify_feed($topic, $token, $mode, $lease);
        return $ret;
    },
    on_ping => sub {
        my ($content_type, $content, $token) = @_;
        $logger->info("Ping received $content_type, token: $token");
        $river->add_feed_content($content);
        return;
    },
);
my $config = eval { LoadFile('config.yml') } || {};

our $feed_update_timer = AnyEvent->timer(interval => 1*60, cb => sub {
    $logger->info("Updating feeds");
    $river->update_feeds;
});

my $root = '/home/peter/pompiedom-river/static/socket.io';

builder {
    enable "LogDispatch", logger => $logger;
    enable "Plack::Middleware::ConditionalGET";
    enable "+Pompiedom::Plack::Middleware::API", db_config => $config->{database}, river => $river;

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
    mount "/rsscloud" => Pompiedom::Plack::App::RSSCloud->new(river => $river)->to_app,
    mount "/session"  => Pompiedom::Plack::App::Session->new()->to_app,
    mount "/feed"     => Pompiedom::Plack::App::Feed->new()->to_app,
    mount "/opml"     => Pompiedom::Plack::App::OPML->new()->to_app,
    mount "/watch"    => Pompiedom::Plack::App::Subscription->new(river=>$river,config=>$config)->to_app,
    mount "/"         => Pompiedom::Plack::App::River->new(river => $river, config=>$config)->to_app,
}

