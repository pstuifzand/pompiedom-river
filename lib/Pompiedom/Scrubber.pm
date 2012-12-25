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

package Pompiedom::Scrubber;
use strict;
use warnings;

use HTML::Scrubber;

sub new {
    my $class = shift;
    my $self = {
        scrubber => _create_scrubber(),
    };
    return bless $self, $class;
}

sub scrub {
    my ($self, $content) = @_;
    return $self->{scrubber}->scrub($content);
}

sub _create_scrubber {
    my $scrubber = HTML::Scrubber->new(allow => [ qw[ ul ol li p b i u hr br em strong pre code tt kbd blockquote q ] ]);

    $scrubber->rules(
        img => {
            src => 1,
            alt => 1,                 # alt attribute allowed
            width => 1,
            height => 1,
            'style' => 1,
            '*' => 0,                 # deny all other attributes
        },
        a => {
            href => 1,
            alt  => 1,
            title => 1,
            'style' => 1,
            '*' => 0,
        },
    );
    return $scrubber;
}

1;
