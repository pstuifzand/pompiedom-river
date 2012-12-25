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

package Pompiedom::Cloud;
use strict;
use warnings;


sub new {
    my $class = shift;
    my $args = shift;

    if (ref($args) ne 'HASH') {
        return;
    }
    my $self = {
        domain => $args->{domain},
        port => $args->{port},
        path => $args->{path},
        register_procedure => $args->{register_procedure} || $args->{registerProcedure},
        protocol => $args->{protocol},
    };

    return bless $self, $class;
}

sub domain {
    my $self = shift;
    return $self->{domain};
}

sub port {
    my $self = shift;
    return $self->{port};
}

sub path {
    my $self = shift;
    return $self->{path};
}

sub register_procedure {
    my $self = shift;
    return $self->{register_procedure};
}

sub protocol {
    my $self = shift;
    return $self->{protocol};
}

1;

