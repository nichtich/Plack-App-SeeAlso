use strict;
package SeeAlso::Format::redirect;
#ABSTRACT: HTTP redirect as response format

use base 'SeeAlso::Format';

sub type { 'text/html' }

sub psgi {
    my ($self, $result) = @_;
    my ($url) = grep { $_ } @{$result->[3]};

    if ($url) {
        return [302, [
            Location => $url, URI => "<$url>",
            'Content-Type' => $self->format
        ], [ "<html><head><meta http-equiv='refresh' content='0; URL=$url'></head></html>" ]
        ]
    } else {
        return [404,['Content-Type' => $self->format],['<html><body>not found</body></html>']];
    }
}

1;

=encoding utf8
