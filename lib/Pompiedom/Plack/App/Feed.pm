package Pompiedom::Plack::App::Feed;

use strict;
use warnings;

use parent 'Plack::Component';

use Plack::Request;
use Plack::Session;
use URI;
use URI::Escape;
use XML::Feed;
use Encode;
use HTML::Entities 'encode_entities_numeric';

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

    if ($req->path_info =~ m{^/post$}) {
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

        $env->{pompiedom_api}->PingFeed2('http://shattr.net:8086/feed/pstuifzand/rss.xml',
                                         "http://shattr.superfeedr.com/");

        $res->content("OK");
    }
    elsif ($req->path_info =~ m{^/(\w+)/rss\.xml$}) {
        my $shortcode = $1;
        my $feed = $env->{pompiedom_api}->FeedGet($shortcode);

        $res->code(200);
        $res->content_type('application/rss+xml; charset=UTF-8');
        my $rss_xml = $feed->as_string;
        $res->content($rss_xml);
        return $res->finalize;
    }
    else {
        return $req->new_response(404, [], 'Not found')->finalize;
    }
    return $res->finalize;
}

1;

