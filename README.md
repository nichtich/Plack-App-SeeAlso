This module implements the SeeAlso Linkserver Protocol as PSGI application.

This module implements the a SeeAlso Linkserver Protocol server as PSGI
application. SeeAlso is basically based on two HTTP protocols, 
[unAPI](http://unapi.info) and [OpenSearch](http://opensearch.org).

To implement a SeeAlso server with this module, just provide a query function:

    $ echo 'use Plack::App::SeeAlso;
    Plack::App::SeeAlso->new( Query => sub {
        my $id = shift;
        return unless $id =~ /:/;
        # ...
        return [ $id, [ "label" ], [ "hello" ], [ "http://example.org" ] ];
    } );' > app.psgi
    
    $ plackup app.psgi &
    HTTP::Server::PSGI: Accepting connections at http://0:5000/
    
    $ curl 'http://0:5000/?format=seealso&id=foo:bar'
    ["foo:bar",["label"],["hello"],["http://example.org"]]

    $ curl 'http://0:5000/?format=seealso&id=foo&callback=bar'
    bar(["foo",[],[],[]])

The module also contains a client interface for easy debugging. See the 
module's documentation for details.
