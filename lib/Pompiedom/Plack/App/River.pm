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

package Pompiedom::Plack::App::River;
use strict;
use warnings;

use parent 'Pompiedom::AppBase';
use Plack::Util::Accessor 'config', 'river';
use Plack::Session;
use Plack::Request;
use Plack::Response;

sub init_handlers {
    my ($self) = @_;

    $self->register_handler('GET', '/', sub {
        my ($self, $env) = @_;
        my $session = Plack::Session->new($env);
        if ($session->get('logged_in')) {
            my $res = Plack::Response->new;
            my $username = $session->get('username');
            $res->redirect('/user/'.$username.'/dashboard');
            return $res->finalize;
        }
        return $self->render_template('index.tt', {}, $env);
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

1;
