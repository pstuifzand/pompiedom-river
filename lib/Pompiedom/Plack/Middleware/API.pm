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

package Pompiedom::Plack::Middleware::API;
use parent 'Plack::Middleware';
use strict;

use Plack::Util::Accessor qw(db_config river);
use Pompiedom::API::Pompiedom;

sub call {
    my $self = shift;
    my $env = shift;

    my $api = Pompiedom::API::Pompiedom->new(
        hostname  => $env->{HTTP_HOST},
        db_config => $self->db_config,
        river     => $self->river,
    );

    $self->river->api($api);

    $self->river->reload_feeds;
    #$self->river->update_feeds;

    $env->{pompiedom_api} = $api;

    return $self->app->($env);
};

1;
