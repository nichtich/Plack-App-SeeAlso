package SeeAlso::Format::redirect;

use base 'SeeAlso::Format';

sub format { 'text/html' }

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
