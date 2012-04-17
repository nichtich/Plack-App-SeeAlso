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
use Scalar::Util qw(blessed);
use JSON;
use Encode;

use parent 'Plack::Component';
use parent 'Exporter';

our @EXPORT = qw(push_seealso);

# properties of the server form OpenSearch Description
our @PROPERTIES; BEGIN { @PROPERTIES = qw(Query Stylesheet Formats Examples
    ShortName LongName Attribution Tags Contact Description Source 
    DateModified Developer); }

use Plack::Util::Accessor @PROPERTIES;

# browsers will more likely complain otherwise
use Plack::MIME;
Plack::MIME->add_type( '.xsl' => 'text/xsl' );

sub prepare_app {
    my $self = shift;
    return if $self->{app}; # already initialized

    # get default values from module variables
    $self->{Stylesheet} = 'seealso.xsl' unless exists $self->{Stylesheet};
    foreach (@PROPERTIES) {
        no strict 'refs';
        $self->$_( ${ref($self)."::$_"} // '' ) unless exists $self->{$_};
    }

    $self->{ShortName}   = sprintf '%.16s',   $self->{ShortName} // '';
    $self->{LongName}    = sprintf '%.48s',   $self->{LongName} // '' ;
    $self->{Description} = sprintf '%.1024s', $self->{Description} // '';
    $self->{Tags}        = sprintf '%.256s',  $self->{Tags} // '';
    $self->{Attribution} = sprintf '%.256s',  $self->{Attribution} // '';

    # TODO: validate
    #   Stylesheet
    #   Formats 
    #   Contact
    #   Source 
    #   DateModified 
    #   Examples

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

    my @xml = '<?xml version="1.0" encoding="UTF-8"?>    
<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/" 
    xmlns:dc="http://purl.org/dc/elements/1.1/" 
    xmlns:dcterms="http://purl.org/dc/terms/" 
    xmlns:seealso="http://ws.gbv.de/seealso/schema/">';

    my @prop = (
        map { $_ => $_ } qw(ShortName LongName Description Tags 
            Contact Developer Attribution),
        DateModified => 'dcterms:modified',
        Source       => 'dc:source',
    );
    while (@prop) {
        my $field = shift @prop;
        my $tag   = shift @prop;
        my $value = $self->{$field} or next;
        push @xml, "  <$tag>"._xmlescape($value)."</$tag>";
    }

    foreach (@{ $self->Examples || [] }) {
        my $id = _xmlescape($_->{id});
        push @xml, "<Query role=\"example\" searchTerms=\"$id\" />";
    }
    
    my $tpl = $base . ($base =~ /\?/ ? '&' : '?')
            . "id={searchTerms}&format=seealso&callback={callback}";
    push @xml, "  <Url type=\"text/javascript\" template=\"" . _xmlescape($tpl) . "\"/>";

    push @xml, '</OpenSearchDescription>','';
 
    return [ 200, [ "Content-Type"
            => 'application/opensearchdescription+xml; charset: utf-8' ],
        [ encode('utf8', join "\n", @xml) ]
    ];
}

sub push_seealso ($$$$) {
    shift if blessed($_[0]);
    my $resp = shift;
    push @{$resp->[1]}, (shift // '');
    push @{$resp->[2]}, (shift // '');
    push @{$resp->[3]}, (shift // '');
    $resp;
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

This module implements the a SeeAlso Linkserver Protocol server as PSGI
application. SeeAlso is basically based on two HTTP protocols, 
L<unAPI|http://unapi.info> and L<OpenSearch|http://opensearch.org> 
(Open Search Suggestions and Open Search Description documents).

You can simply implement a SeeAlso server by creating an instance of 
Plack::App::SeeAlso or by deriving this class and implementing

This module contains a SeeAlso client in form of three files (seealso.js,
seealso.xsl, seealso.css). This client is served if no format-parameter
was given, so you get a nice, human readable interface.

=head1 SYNOPSIS

    # create SeeAlso server with code reference
    use Plack::App::SeeAlso;
    my $app = Plack::App::SeeAlso->new( 
        Query => sub {
            my $id = shift;
            return unless $id =~ /:/; # return undef for empty response
            
            # ... create and return response            
            return [ $id, [ "label" ], 
                          [ "hello" ], 
                          [ "http://example.org" ] ];

            # ... alternatively create with 'push_seealso'
            push_seealso [$id], "label", "hello", "http://example.org";
        }, ShortName => 'My Server' 
    );

    # create SeeAlso server as subclass
    use parent 'Plack::App::SeeAlso';

    our $ShortName   = 'My Server';
    our $Contact     = 'admin@example.org';
    our $Description = '...';

    sub query {
        my ($self, $id) = @_;
        # ...
    }

=method new ( [ %properties ] )

Creates a new SeeAlso server. The following optional properties are supported,
most of them to be used as OpenSearch description elements:

=over 4

=item B<Query>

A code reference to be used as query method.

=item B<ShortName>

Short name of the server (truncated to 16 characters).

=item B<LongName>

Long name of the server (truncated to 48 characters).

=item B<Description>

Verbal description of the server (truncated to 1024 characters).

=item B<Contact>

An email address at which the maintainer of the server can be reached.

=item C<Developer>

Human-readable name or identifier of the creator or maintainer of the server.

=item B<Tags>

A set of words that are used as keywords to identify and categorize the server.
Tags must be a single word and are delimited by the space character (truncated
to 256 characters).

=item B<Attribution>

A list of all sources or entities that should be credited for the content 
contained in the search feed (truncated to 256 characters).

=item B<Source>

Verbal description of the source of the server (Dublin Core element dc:source).

=item B<DateModified>

Timestamp of last modification of the server (qualified Dublin Core element
Date.Modified).

=item B<Examples>

A list of hash reference with C<id> examples and optional C<response> data,
such as the following structure:
    
    [ 
      { id => 'foo' }, 
      { id => 'bar', 
        response => [ 'bar', ['label'],['description'],['uri'] ] }
    ]

=item B<Stylesheet>

By default, an client interface is returned at C</seealso.xsl>, C</seealso.js>,
and C</seealso.css>. A link to the interface is added if no format parameter
was given. You can disable this interface by setting the Stylesheet option to 
undef or you set it to some URL of another XSLT file.

=item B<Formats>

A hash reference with additional formats, to be used with L<Plack::App::unAPI>.

=back

The OpenSearch description element B<Url> is set automatically. The elements
B<SyndicationRight>, B<AdultContent>, B<Language>, B<InputEncoding>, and
B<OutputEncoding> are not supported.

=method query ( $identifier )

If you subclass this module, you are expected to implement a C<query> method.
The method receives a defined identifier (set to the empty string by default)
as an argument and is expected to return either an Open Search Suggestions
response or C<undef>.  An Open Search Suggestions response is an array
reference with two to three elements:

=over

=item

The first element is the B<identifier>, possibly normalized.

=item

The second element is an array reference with C<labels> as strings.

=item

The third element is an array reference with C<descriptions> as strings.

=item

The fourth element is an arary reference with C<URIs> as strings.

=back

=method push_seealso ( $response, $label, $description, $uri )

This utility method/function is exported by default. You can use it to append
a single response item to a response array reference:

    $resp = [$id,[],[],[]];
    push_seealso $resp, $label, $descr, $uri;
    # $resp is now [$id,[$label],[$descr],[$uri]];

=head1 NOTES

This module sets the default MIME type for C<.xsl> files to C<text/xsl> because
browser will more likely complain otherwise. This setting is done with
L<Plack::MIME> and it may also affect other applications.

=head1 SEE ALSO

This module is basically a refactored clean-up of L<SeeAlso::Server>. The unAPI
handling is done by module L<Plack::App::unAPI>. An introductionary article
about unAPI can be found at L<http://www.ariadne.ac.uk/issue57/voss/>.

=cut
