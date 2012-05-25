package Pompiedom::Plack::App::River;
use strict;
use warnings;

use parent 'Plack::Component';
use Plack::Util::Accessor 'config', 'river';
use Plack::Session;
use Plack::Request;
use Encode;
use Template;

use Date::Period::Human;

my %handlers = (
    GET  => [],
    POST => [],
);

sub register_handler {
    my ($method, $prefix, $handler) = @_;
    push @{$handlers{$method}}, HandlerFunc->new($prefix, $handler);
    return;
}

sub call {
    my ($self, $env) = @_;
    my $req = Plack::Request->new($env);

    my $handler;
    for my $h (@{$handlers{$req->method}}) {
        my $prefix = $h->[0];
        if ($req->path_info =~ m/^$prefix/) {
            $handler = $h->[1];
            last;
        }
    }
    if ($handler) {
        return $handler->($self, $env);
    }
    return $req->new_response(404, [], 'Not found')->finalize;
}

sub prepare_app {
    my ($self) = @_;

    my $templ = Template->new({
        INCLUDE_PATH => ['template/custom', 'templates/default' ],
        ENCODING     => 'utf8',
    });

    $self->{template} = $templ;

    register_handler('GET', '/', sub {
        my ($self, $env) = @_;
        my $params = $self->_build_messages_template_params($env);
        return $self->render_template('pompiedom_river.tt', $params, $env);
    });
    register_handler('GET', '/about', sub {
        my ($self, $env) = @_;
        return $self->render_template('about.tt', {}, $env);
    });
    register_handler('POST', '/seen', sub {
        my ($self, $env) = @_;
        my $session = Plack::Session->new($env);
        my $req = Plack::Request->new($env);
        my $res  = $req->new_response();

        my $guid = $req->param('guid');

        $env->{pompiedom_api}->{db}->FeedItemSeen($guid);

        $res->content('OK');

        return $res->finalize;
    });

    # Sort handlers
    for my $method (keys %handlers) {
        @{$handlers{$method}} = sort {length($b->[0]) <=> length($a->[0]) } @{$handlers{$method}};
    }

    return;
}

sub template {
    my $self = shift;
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

sub _build_messages_template_params {
    my ($self, $env) = @_;

    my $session = Plack::Session->new($env);
    my $req = Plack::Request->new($env);

    my $ft = DateTime::Format::RFC3339->new();
    my $dp = Date::Period::Human->new({lang => 'en'});

    my @messages;

    for my $m ($self->river->messages) {
        next if $env->{pompiedom_api}->{db}->HaveFeedItemSeen($m->{id});

        # FIX for twitters feeds, which doesn't work
        if ($m->{title} && $m->{message} && ($m->{title} eq $m->{message})) {
            delete $m->{title};
        }

        $m->{datetime}       = $ft->parse_datetime($m->{timestamp});
        $m->{human_readable} = ucfirst($dp->human_readable($m->{datetime}));

        push @messages, $m;
    }

    @messages = splice @messages, 0, 12;

    my $url = $req->param('link') || $req->param('url');
    $url = decode("UTF-8", $url);

    return {
        river    => $self->river,
        messages => \@messages,
        config   => $self->config,
        args     => {
            link  => $url,
            title => decode("UTF-8", scalar $req->param('title')),
            description  => decode("UTF-8", scalar $req->param('description')),
        },
        feeds => $env->{pompiedom_api}->UserFeeds($session->get('username')),
    };
}

package HandlerFunc;
sub new {
    my ($klass, $prefix, $handler) = @_;
    return bless [$prefix,$handler], $klass;
}

1;
