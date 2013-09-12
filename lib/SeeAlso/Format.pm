use strict;
package SeeAlso::Format;
#ABSTRACT: Response format

use Plack::Request;
use Try::Tiny;
use Data::Dumper;

use Scalar::Util qw(reftype);
use Carp qw(croak);

use SeeAlso::Format::seealso;
use SeeAlso::Format::redirect;

sub valid {
    my $resp = shift;
    return unless (reftype($resp) || '') eq 'ARRAY' and @$resp == 4;
    return if ref($resp->[0] // []); # identifier must be string
    return unless (reftype($resp) || '') eq 'ARRAY';
    foreach (1,2,3) {
        my $a = $resp->[$_];
        return unless (reftype($a) || '') eq 'ARRAY';
        return if grep { ref($_ // []) } @$a;
    }
    $resp;
}

sub new {
    my $class = shift;

    if (@_) {
        $class = "SeeAlso::Format::".lc($_[0]);
        eval "require $class"; 
        croak $@ if $@;
    }

    bless { }, $class;
}

sub type {
    die __PACKAGE__ . '->type must return a MIME type';
}

sub psgi {
    die __PACKAGE__ . '->psgi must return a PSGI response';
}

sub app {
    my ($self, $query) = @_;
    sub {
        my $env = shift;
        my $id = Plack::Request->new($env)->param('id');
        my $result;
        try {
            $result = $query->( $id );
            die 'Invalid SeeAlso response:' . Dumper($result)
                if defined $result and !valid($result);
        } catch {
            $env->{'psgi.errors'}->print($_);
        };
        $result = [$id,[],[],[]] unless $result;

        return $self->psgi( $result );
    }
}

1;

=head1 SYNOPSIS

    {
        package SeeAlso::Format::plaintext;

        sub type { 'text/plain' };
        sub psgi { [200,[],[]] } # TODO
    }

    use SeeAlso::Format;
    my $plaintext = SeeAlso::Format->new('plaintext');

=head1 DESCRIPTION

Subclasses must implement a method C<type> that returns a mime type, and a
method C<psgi> that returns a L<PSGI> response, given a SeeAlso response.

=encoding utf8
