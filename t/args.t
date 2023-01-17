#!/usr/bin/env perl
use strict;
use warnings;
use lib ( './lib', '../lib' );
use feature    qw(say);
use File::Temp qw{ tempfile };    # core
use Data::Dumper;
use Convert::Pheno;
use Test::More tests => 2;
use File::Compare;

use_ok('Convert::Pheno') or exit;

my $input = {
    bff2pxf => {
        in_file => 't/bff2pxf/in/individuals.json',
        out     => 't/bff2pxf/out/pxf.json'
    }
};

#for my $method (qw/redcap2bff/){
for my $method ( sort keys %{$input} ) {

    # Create Temporary file
    my ( undef, $tmp_file ) =
      tempfile( DIR => 't', SUFFIX => ".json", UNLINK => 1 );

    #say "################";
    my $convert = Convert::Pheno->new(
        {
            in_file     => $input->{$method}{in_file},
            in_textfile => 1,
            test        => 1,
            debug       => 5,                            # Check that debug does not interfere
            method      => $method
        }
    );
    io_yaml_or_json(
        {
            filename => $tmp_file,
            data     => $convert->$method,
            mode     => 'write'
        }
    );
    ok( compare( $input->{$method}{out}, $tmp_file ) == 0, $method );
}
