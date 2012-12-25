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

package Pompiedom::Plack::App::RSSCloud;
use strict;
use warnings;
use parent qw/Plack::Component/;

use Plack::Util::Accessor qw(river);
use Plack::Request;
use URI;
use URI::Escape;
use XML::Feed;

sub notify {
    my ($self, $env, $req) = @_;
    my $body = $req->raw_body;
    my ($url) = ($body =~ m/^url=(.+)$/);
    $url = uri_unescape($url);
    my $uri = URI->new($url);
    $self->river->add_feed($url);
    return $req->new_response(200, [], "Rocks!")->finalize;
}

sub call {
    my $self = shift;
    my $env = shift;

    my $req = Plack::Request->new($env);

    if ($req->path_info =~ m{^/notify}) {
        return $self->notify($env, $req);
    }

    $req->new_response(404, [], 'Not found')->finalize;
}

1;

