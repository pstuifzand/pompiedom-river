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

sub call {
    my ($self, $env) = @_;
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

        my @messages;

        for my $m ($self->river->messages) {
            next if $env->{pompiedom_api}->{db}->HaveFeedItemSeen($m->{id});

            # FIX for twitters feeds
            if ($m->{title} && $m->{message} && ($m->{title} eq $m->{message})) {
                delete $m->{title};
            }

            $m->{datetime}       = $ft->parse_datetime($m->{timestamp});
            $m->{human_readable} = ucfirst($dp->human_readable($m->{datetime}));

            push @messages, $m;
        }

        my $url = $req->param('link') || $req->param('url');
        $url = decode("UTF-8", $url);

        $templ->process('pompiedom_river.tt', { 
            session => {
                username  => $session->get('username'),
                logged_in => $session->get('logged_in'),
            },
            river    => $self->river,
            messages => \@messages,
            config   => $self->config,
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
    elsif ($req->path_info =~ m{^/seen$}) {
        my $guid = $req->param('guid');
        $env->{pompiedom_api}->{db}->FeedItemSeen($guid);
        if ($req->method eq 'POST') {
            $res->content('OK');
        }
        else {
            $res->redirect('/');
        }
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
    else {
        return $req->new_response(404, [], 'Not found')->finalize;
    }
    return $res->finalize;
}


1;

