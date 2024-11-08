#!/usr/bin/env perl
use strict;
use warnings;
use lib ( './lib', '../lib' );
use feature qw(say);
use Data::Dumper;
use JSON::XS;
use Test::More tests => 2;
use Test::Deep;
use Convert::Pheno;

use_ok('Convert::Pheno') or exit;

# Load data from files
my $bff = read_first_json_object('t/bff2pxf/in/individuals.json');
my $pxf = read_first_json_object('t/bff2pxf/out/pxf.json');

# Ignoring variable fields
$pxf->{$_} = ignore() for (qw(id metaData));

my $input = { bff2pxf => { data => $bff } };

# Tests
for my $method ( sort keys %{$input} ) {
    my $convert = Convert::Pheno->new(
        {
            in_textfile => 0,
            data        => $input->{$method}{data},
            method      => $method
        }
    );

    cmp_deeply( $convert->$method, $pxf, $method );
}

# Utility subroutine to read the first JSON object from a file containing a JSON array
sub read_first_json_object {
    my ($filename) = @_;
    open my $fh, '<', $filename or die "Could not open '$filename': $!";
    local $/;  # Enable slurp mode to read the entire file
    my $json_text = <$fh>;
    close $fh;

    # Decode the JSON text as an array
    my $json_array = decode_json($json_text);

    # Return the first element if the decoded JSON is an array
    return ref $json_array eq 'ARRAY' ? $json_array->[0] : die "Expected a JSON array in $filename";
}
