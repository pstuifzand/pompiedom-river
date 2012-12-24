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
