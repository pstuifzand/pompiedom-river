# Copyright (c) 2010-2013 Peter Stuifzand
# Copyright (c) 2010-2013 Other contributors as noted in the AUTHORS file
# 
# This file is part of Pompiedom.
# 
# Pompiedom is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
# 
# Pompiedom is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

package Pompiedom::Plack::App::Feed;

use strict;
use warnings;

use parent 'Pompiedom::AppBase';

use Plack::Request;
use Plack::Session;
use URI;
use URI::Escape;
use XML::Feed;
use Encode;
use HTML::Entities 'encode_entities_numeric';

sub init_handlers {
    my $self = shift;

    $self->register_handler('POST', '/post', sub {
        my ($self, $env) = @_;
        my $req = Plack::Request->new($env);
        my $res = $req->new_response(200);

        my $session = Plack::Session->new($env);

        if (!$session->get('logged_in')) {
            $res->redirect($req->script_name . '/');
            return $res->finalize;
        }
        
        my $shortcode = $req->param('feed');

        my $title = $req->param('title');
        my $link = $req->param('link');
        my $description = $req->param('description');

        $env->{pompiedom_api}->UserPostItem($shortcode, { title => $title,'link' => $link, description => $description });

        $env->{pompiedom_api}->PingFeed($shortcode);

        $env->{pompiedom_api}->PingFeed2('http://shattr.net:8086/feed/'.$shortcode.'/rss.xml',
                                         "http://shattr.superfeedr.com/");

        $res->content("OK");

        return $res->finalize;
    });

    $self->register_handler('GET', '/create_post', sub {
        my ($self, $env) = @_;
        my $req = Plack::Request->new($env);
        my $session = Plack::Session->new($env);

        my $title = $req->param('title');
        my $description = $req->param('description');
        my $url = $req->param('link') || $req->param('url');
        $url = decode("UTF-8", $url);

        return $self->render_template('post.tt', {
                args =>  {
                    link  => $url,
                    title => decode("UTF-8", scalar $req->param('title')),
                    description  => decode("UTF-8", scalar $req->param('description')),
                },
                feeds => $env->{pompiedom_api}->UserFeeds($session->get('username')),
            }, $env);
    });

    $self->register_handler('GET', qr{/(\w+)/rss\.xml}, sub {
        my ($self, $env, $params) = @_;

        my $shortcode = $params->[0];

        my $feed = $env->{pompiedom_api}->FeedGet($shortcode);

        my $res = Plack::Response->new;
        $res->code(200);
        $res->content_type('application/rss+xml; charset=UTF-8');
        my $rss_xml = $feed->as_string;
        $res->content($rss_xml);
        return $res->finalize;
    });

    return;
}

1;

