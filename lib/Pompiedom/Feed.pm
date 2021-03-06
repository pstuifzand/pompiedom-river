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

package Pompiedom::Feed;
use strict;
use Pompiedom::Cloud;
use DateTime::Format::MySQL;

sub new {
    my $class = shift;

    my $args = shift;

    my $self = {};

    for (qw/id url mode status hub token/) {
        $self->{$_} = $args->{$_};
    }
    
    for (qw/updated subscribed created changed/) {
        eval {
            $self->{$_} = DateTime::Format::MySQL->parse_datetime($args->{$_});
        };
        if ($@) {
            $self->{$_} = DateTime->now() - DateTime::Duration->new(years => 1);
        }
    }

    my $cloud = {};

    for (qw/domain port path register_procedure protocol/) {
        $cloud->{$_} = $args->{$_};
    }

    if ($cloud->{domain} && $cloud->{port}) {
        $self->{cloud} = Pompiedom::Cloud->new($cloud);
    }

    $self->{mode} ||= 'subscribe';

    return bless $self, $class;
}

sub id {
    my $self = shift;
    return $self->{id};
}

sub url {
    my $self = shift;
    return $self->{url};
}

sub name {
    my ($self, $name) = @_;
    $self->{name} = $name if $name;
    return $self->{name};
}

sub mode {
    my ($self, $mode) = @_;
    $self->{mode} = $mode if $mode;
    return $self->{mode};
}

sub status {
    my ($self, $status) = @_;
    $self->{status} = $status if $status;
    return $self->{status};
}

sub hub {
    my ($self, $hub) = @_;
    $self->{hub} = $hub if $hub;
    return $self->{hub};
}

sub token {
    my ($self, $token) = @_;
    $self->{token} = $token if $token;
    return $self->{token};
}

sub updated {
    my ($self, $updated) = @_;
    $self->{updated} = $updated if $updated;
    return $self->{updated};
}

sub subscribed {
    my ($self, $subscribed) = @_;
    $self->{subscribed} = $subscribed if $subscribed;
    return $self->{subscribed};
}

sub created {
    my ($self, $created) = @_;
    $self->{created} = $created if $created;
    return $self->{created};
}

sub changed {
    my ($self, $changed) = @_;
    $self->{changed} = $changed if $changed;
    return $self->{changed};
}

sub cloud {
    my ($self, $cloud) = @_;
    $self->{cloud} = $cloud if $cloud;
    return $self->{cloud};
}

1;

