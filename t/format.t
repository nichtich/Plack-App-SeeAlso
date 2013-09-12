use strict;
use Test::More;
use HTTP::Request::Common;
use Plack::Test;
use Module::Loaded;

{
    package SeeAlso::Format::dump;
    use Data::Dumper;

    sub type { 'text/plain' }
    sub psgi {
        my ($self,$seealso) = @_;
        local $Data::Dumper::Terse = 1;
        local $Data::Dumper::Useqq = 1;
        [200,['Content-Type' => 'text/plain'],[Dumper($seealso)]]; 
    }
}
mark_as_loaded('SeeAlso::Format::dump');

use SeeAlso::Format;
my $dump = SeeAlso::Format->new('dump');
isa_ok( $dump, 'SeeAlso::Format::dump' );

my $seealso = ['my:id',["example"],["Example\nResponse"],["http://example.org/"]];
my $res = $dump->psgi( $seealso );

is $res->[2]->[0], <<'DUMP', 'dump format';
[
  "my:id",
  [
    "example"
  ],
  [
    "Example\nResponse"
  ],
  [
    "http://example.org/"
  ]
]
DUMP

{
    package MySeeAlsoServer;

    use parent 'Plack::App::SeeAlso';

    sub format_dump {
        # TODO: implemented by SeeAlso::Format::dump
    }

    sub format_foo {
        # TODO: return PSGI response
    }
}

my $app = MySeeAlsoServer->new;

test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->(GET "/?id=x:y");
    #   is( $res->code, 200, 'found');
    note explain $res->content;
};

done_testing;
