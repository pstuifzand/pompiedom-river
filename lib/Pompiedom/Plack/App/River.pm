package Pompiedom::Plack::App::River;
use strict;
use warnings;

use parent 'Pompiedom::AppBase';
use Plack::Util::Accessor 'config', 'river';
use Plack::Session;
use Plack::Request;
use Encode;

use Date::Period::Human;
use Data::Dumper;

sub init_handlers {
    my ($self) = @_;

    $self->register_handler('GET', '/', sub {
        my ($self, $env) = @_;
        my $session = Plack::Session->new($env);
        if ($session->get('logged_in')) {
            my $params = $self->_build_messages_template_params($env);
            return $self->render_template('pompiedom_river.tt', $params, $env);
        }
        else {
            return $self->render_template('index.tt', {}, $env);
        }
    });

    $self->register_handler('GET', '/about', sub {
        my ($self, $env) = @_;
        return $self->render_template('about.tt', {}, $env);
    });

    $self->register_handler('POST', '/seen', sub {
        my ($self, $env) = @_;
        my $session = Plack::Session->new($env);
        my $req = Plack::Request->new($env);
        my $res  = $req->new_response(200);

        my $guid = $req->param('guid');

        $env->{pompiedom_api}->{db}->FeedItemSeen($guid);

        $res->content('OK');

        return $res->finalize;
    });

    return;
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

    #@messages = splice @messages, 0, 12;

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

1;
