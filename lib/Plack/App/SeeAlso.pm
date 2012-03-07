use strict;
use warnings;
package Plack::App::SeeAlso;
#ABSTRACT: SeeAlso Server as PSGI application

use feature ':5.10';

use Plack::Request;
use Plack::Middleware::JSONP;
use Plack::Middleware::Static;
use Plack::App::unAPI '0.3';
use File::ShareDir qw(dist_dir);
use Plack::Util;
use Carp qw(croak);
use JSON;
use Encode;

use parent 'Plack::Component';
use Plack::Util::Accessor qw(
    Query Stylesheet Formats
    ShortName LongName Description Source DateModified Examples 
);

# browsers will more likely complain otherwise
use Plack::MIME;
Plack::MIME->add_type( '.xsl' => 'text/xsl' );

sub prepare_app {
    my $self = shift;
    return if $self->{app}; # already initialized

    # TODO: validate options (truncate ShortName etc.)

    $self->{Stylesheet} = "seealso.xsl" unless exists $self->{Stylesheet};

    my %formats = %{ $self->{Formats} || { } };
    delete $formats{$_} for (qw(opensearchdescription seealso _));

    my $app = unAPI(
            opensearchdescription => [
                sub { $self->openSearchDescription(@_); }
                => 'application/opensearchdescription+xml', 
            ],
            seealso => [
                sub {
                    my $id = Plack::Request->new(shift)->param('id');
                    my $res = $self->query( $id ) || [$id,[]];
                    # TODO: validate?
                    my $json = JSON->new->encode( $res );
                    return [ 200, [ "Content-Type" => 'text/javascript' ], [ $json ] ];
                } => 'text/javascript' ],

            # never return format list if format parameter given
            _ => { always => 1 }, 

            %formats # additional formats
        );
    
    $app = Plack::Middleware::JSONP->wrap($app);

    if ($self->{Stylesheet}) {
        $app = Plack::Middleware::Static->wrap( $app,
            path => qw{seealso\.(js|xsl|css)$},
            root => dist_dir('Plack-App-SeeAlso')
        );
    }

    $self->{app} = $app;
}

sub query {
    my ($self, $id) = @_;
    return ( $self->{Query} ? $self->{Query}->( $id ) : [$id,[]] );
}

sub call {
    my ($self, $env) = @_;

    my $result = $self->{app}->( $env );

    Plack::Util::response_cb( $result, sub {
        my $res = shift;
        return unless $res->[0] == 300;
        my $base = Plack::Request->new($env)->base; 
        my $xsl = $self->{Stylesheet};
        $xsl = '<?xml-stylesheet type="text/xsl" href="'.$xsl.'"?>';
        $xsl .= "\n<?seealso-query-base $base?>\n";
        $res->[2]->[0] =~ s{\?>\s+<formats}{?>\n$xsl<formats}ms;
    } ) if $self->{Stylesheet};

    return $result;
}

sub openSearchDescription {
    my ($self, $env) = @_;
    my $base = Plack::Request->new($env)->base; 

    my @xml = <<XML;
<?xml version="1.0" encoding="UTF-8"?>    
<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/" 
  xmlns:dc="http://purl.org/dc/elements/1.1/" 
  xmlns:dcterms="http://purl.org/dc/terms/" 
  xmlns:seealso="http://ws.gbv.de/seealso/schema/">
XML

    my %prop = (
        DateModified => 'dcterms:modified',
        Source       => 'dc:source',
        map { $_ => $_ } qw(ShortName LongName Description),
    );
    while (my ($field,$tag) = each %prop) {
        my $value = $self->{$field} or next;
        push @xml, "<$tag>"._xmlescape($value)."</$tag>";
    }

    foreach (@{ $self->Examples || [] }) {
        my $id = _xmlescape($_->{id});
        push @xml, "<Query role=\"example\" searchTerms=\"$id\" />";
    }
    
    my $tpl = $base . ($base =~ /\?/ ? '&' : '?')
            . "id={searchTerms}&format=seealso&callback={callback}";
    push @xml, "  <Url type=\"text/javascript\" template=\"" . _xmlescape($tpl) . "\"/>";

    push @xml, '</OpenSearchDescription>';
 
    return [ 200, [ "Content-Type"
            => 'application/opensearchdescription+xml; charset: utf-8' ],
        [ encode('utf8', join "\n", @xml) ]
    ];
}

# Replace &, <, >, " by XML entities.
sub _xmlescape {
    my $xml = shift;
    if ($xml =~ /[\&\<\>"]/) {
        $xml =~ s/\&/\&amp\;/g;
        $xml =~ s/\</\&lt\;/g;
        $xml =~ s/\>/\&gt\;/g;
        $xml =~ s/"/\&quot\;/g;
    }
    return $xml;
}

1;

=head1 DESCRIPTION

This implements a SeeAlso Linkserver Protocol (SeeAlso) server as PSGI
application. SeeAlso is based on unAPI and OpenSearch.

This module contains a SeeAlso client in form of three files (seealso.js,
seealso.xsl, seealso.css). This client is served if no format-parameter
was given, so you get a nice, human readable interface.

=method new ( [ %options ] )

Creates a new SeeAlso server. Supported options are:

=over 4

=item ShortName

Short name of the server (truncated to 16 characters)

=item LongName

Long name of the server (truncated to 48 characters)

=item Description

Verbal description of the server (truncated to 1024 characters)

=item Source

Verbal description of the source of the server (for Dublin Core element
dc:source)

=item DateModified

Date/Time of last modification of the server (for qualified Dublin Core element
Date.Modified)

=item Examples

A list of hash reference with C<id> examples and optional C<response> data.

=item Stylesheet

By default, an client interface is returned at C</seealso.xsl>, C</seealso.js>,
and C</seealso.css>. A link to the interface is added if no format parameter
was given. You can disable this interface by setting the Stylesheet option to 
undef or you set it to some URL of another XSLT file.

=item Formats

A hash reference with additional formats, for L<Plack::App::unAPI>.

=item Query

A code reference to use as query method.

=back

=method query ( $identifier )

You are expected to implement a C<query> method. It receives a defined
identifier (set to the empty string by default) as an argument and is expected
to return either an Open Search Suggestions response or C<undef>.  An Open
Search Suggestions response is an array reference with two to three elements:

=over

=item

The first element is the identifier, possibly normalized

=item

The second, third, and fourth elements are array references with
strings.

=back

=head1 NOTES

This module sets the default MIME type for c<.xsl> files to C<text/xsl> because
browser will more likely complain otherwise. This setting is done with
L<Plack::MIME> and it may also affect other applications.

=head1 SEE ALSO

This module is basically a refactored clean-up of L<SeeAlso::Server>. The
unAPI handling is put in the module L<Plack::App::unAPI>.

=cut
