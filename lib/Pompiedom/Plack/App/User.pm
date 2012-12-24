package Pompiedom::Plack::App::User;
use parent 'Pompiedom::AppBase';
use Plack::Util::Accessor 'config', 'river';
use Plack::Session;
use Plack::Request;
use Encode;

use Date::Period::Human;
use Data::Dumper;

sub init_handlers {
    my ($self) = @_;

    $self->register_handler(POST => qr{/create}, sub {
        my ($self, $env, $params) = @_;

        my $req = Plack::Request->new($env);

        my $fullname = $req->param('fullname');
        my $username = $req->param('username');
        my $password = $req->param('password');

        $env->{pompiedom_api}->CreateUser({
            fullname => $fullname,
            username => $username,
            password => $password,
        });

        my $res = Plack::Response->new;
        $res->redirect($req->script_name . '/..');
        return $res->finalize;
    });
    $self->register_handler(GET => qr{/(\w+)/dashboard}, sub {
        my ($self, $env, $params) = @_;
        my $params = $self->_build_messages_template_params($env, $params->[0]);
        return $self->render_template('pompiedom_river.tt', $params, $env);
    });
    $self->register_handler(GET => qr{/(\w+)/following}, sub {
        my ($self, $env, $params) = @_;
        my $session = Plack::Session->new($env);
        my $req = Plack::Request->new($env);

        if ($session->get('username') ne $params->[0]) {
            my $res = Plack::Response->new;
            $res->redirect($req->script_name . '/' . $params->[0] . '/dashboard');
            return $res->finalize;
        }

        my @feeds = $env->{pompiedom_api}->GetUserFeeds($params->[0]);
        return $self->render_template('following.tt', { feeds => \@feeds }, $env);
    });
    $self->register_handler(POST => qr{/(\w+)/follow}, sub {
        my ($self, $env, $params) = @_;
        my $req = Plack::Request->new($env);
        my $session = Plack::Session->new($env);

        my $url = $req->param('url');
        print "$url\n";

        $self->river->add_feed($url, remember_feed => 1, callback => sub {
            $self->river->subscribe_cloud($url);
            $env->{pompiedom_api}->UserFollow($session->get('username'), $url);
        });

        my $res = Plack::Response->new;
        $res->redirect($req->script_name . '/' . $params->[0] . '/following');
        return $res->finalize;
    });
}

sub _build_messages_template_params {
    my ($self, $env, $username) = @_;

    my $session = Plack::Session->new($env);
    my $req = Plack::Request->new($env);

    my $ft = DateTime::Format::RFC3339->new();
    my $dp = Date::Period::Human->new({lang => 'en'});

    my @messages;

    for my $m ($self->river->messages_for_user($username)) {
        next if $env->{pompiedom_api}->{db}->HaveFeedItemSeen($m->{id});

        if ($m->{timestamp}) {
            $m->{datetime}       = $ft->parse_datetime($m->{timestamp});
            $m->{human_readable} = ucfirst($dp->human_readable($m->{datetime}));
        }

        push @messages, $m;
    }

    # Less messages...
    #@messages = splice @messages, 0, 12;

    my $url = $req->param('link') || $req->param('url');
    $url = decode("UTF-8", $url);

    return {
        current_username => $username,
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
