use strict;
use warnings;
use Test::More;
use Plack::Test;
use HTTP::Request::Common;

use Plack::App::SeeAlso;

{
    package Foo;
    use parent 'Plack::App::SeeAlso';

    our $ShortName = 'The ShortName is truncated';
    our $Contact   = 'admin@example.com';
}

my $app = Foo->new(
    Developer => 'admin@example.org',
);

sub read_file { do { local( @ARGV, $/ ) = $_[0] ; <> } }

test_psgi $app, sub {
    my $cb  = shift;

    my $res = $cb->(GET "/?format=opensearchdescription");
    is( $res->content, read_file('t/osd1.xml'), 'OSD XML' );

    $res = $cb->(GET "/");
    like( $res->content, qr{<\?xml-stylesheet}, 'has stylesheet');
};

done_testing;
