#!/usr/bin/env perl
use strict;
use warnings;
use feature qw(say);
while (<>) {
    chomp;

    # Skip comments or lines without '|'
    unless (/^#/ || !/\|/) {
        s/^\s+\|//;                     # Remove leading spaces followed by '|'
        my @fields = split /\|/;
        shift @fields;                 # Remove the first element

        # Process and format each field
        @fields = map {
            s/^\s+|\s+$/ /g;          # Trim leading and trailing spaces with a space
            s/\.visit/\._visit/;      # Replace .visit with ._visit
            sprintf "%-60s", $_;      # Format to 60 characters
        } @fields;

        $_ = '| ' . join('|', @fields) . " |";
    }
    say;
}
