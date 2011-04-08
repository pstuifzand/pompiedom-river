use 5.10.0;
use lib 'lib';

use strict;
use warnings;

use Plack::Builder;
use Log::Dispatch;
use Encode;

use Pompiedom::Plack::App::River;
use Pompiedom::River::Messages;

use Date::Period::Human;
use Data::Dumper;

use YAML 'LoadFile';

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
            river    => $river,
            config   => $config,
        }, \$out, {binmode => ":utf8"}) || die "$Template::ERROR\n";

        $res->content_type('text/html; charset=utf-8');
        $res->content(encode_utf8($out));
    }
    elsif ($req->path_info =~ m{^/watch$}) {
        my $feed = $req->param('feed');
        $templ->process('pompiedom_river_watch.tt', { 
                feed   => $feed,
                river  => $river,
                config => $config,
            }, \$out) || die "$Template::ERROR\n";
        $res->content_type('text/html; charset=UTF-8');
        $res->content(encode_utf8($out));
    }
    elsif ($req->path_info =~ m{^/watch/re$}) {
        $river->reload_feeds;
        $res->redirect($req->script_name . '/watch');
    }
    elsif ($req->path_info =~ m{^/watch/add$}) {
        $river->add_feed($req->param('url'), remember_feed => 1);
        $res->redirect($req->script_name . '/watch');
    }
    elsif ($req->path_info =~ m{^/watch/sub$}) {
        $river->subscribe_cloud($req->param('feed'));
        $res->redirect($req->script_name . '/watch');
    }
    elsif ($req->path_info =~ m{^/about$}) {
        $res->content_type('text/html; charset=UTF-8');
        $templ->process('about.tt', {}, \$out) || die "$Template::ERROR\n";
        $res->content(encode_utf8($out));
    }
    elsif ($req->path_info =~ m{^/debug$}) {
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

    enable "Static", path => sub { s!^/static/!! }, root => 'static';
    mount "/rsscloud" => Pompiedom::Plack::App::River->new(river => $river)->to_app,
    mount "/"         => $app;
}

