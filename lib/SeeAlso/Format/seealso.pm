package SeeAlso::Format::seealso;
use strict;
use warnings;

use base 'SeeAlso::Format';

sub type { 'text/javascript' } 

sub psgi {
    my ($self, $result) = @_;
    my $json = JSON->new->encode( $result );
    return [ 200, [ "Content-Type" => $self->type ], [ $json ] ];
}

1;
