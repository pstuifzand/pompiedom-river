package Pompiedom::River::Messages;
use strict;
use warnings;

sub new {
    my $klass = shift;
    my $self = { messages => [], ids => {} };
    return bless $self, $klass;
}


sub add_message {
    my ($self, $message) = @_;
    $self->{ids}{$message->{id}} = 1;
    push @{$self->{messages}}, $message;
}

sub has_message {
    my ($self, $id) = @_;
    return $self->{ids}{$id};
}

sub messages {
    my $self = shift;
    return @{$self->{messages}};
}

1;
