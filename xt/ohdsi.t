#!/usr/bin/env perl
use strict;
use warnings;
use lib ( './lib', '../lib' );
use feature qw(say);
use Data::Dumper;
use File::Temp qw{ tempfile };    # core
use Test::More tests => 2;
use File::Compare;
use Convert::Pheno;

use_ok('Convert::Pheno') or exit;

my $input = {
    omop2bff => {
        in_file  => undef,
        in_files => [
            't/omop2bff/in/CONCEPT.csv', 't/omop2bff/in/DRUG_EXPOSURE.csv',
            't/omop2bff/in/PERSON.csv'
        ],
        ohdsi_db => 1,
        out      => 't/omop2bff/out/ohdsi.json'
    }
};

for my $method ( sort keys %{$input} ) {

    # Create Temporary file
    my ( undef, $tmp_file ) =
      tempfile( DIR => 't', SUFFIX => ".json", UNLINK => 1 );

    my $convert = Convert::Pheno->new(
        {
            in_files    => $input->{$method}{in_files},
            in_textfile => 1,
            test        => 1,
            stream      => 0,
            omop_tables => [],
            out_file    => $tmp_file,
            search      => 'exact',
            ohdsi_db    => $input->{$method}{'ohdsi_db'},
            method      => $method
        }
    );

  SKIP: {
        skip qq{because 'share/db/ohdsi.db' is required with <ohdsi_db>}, 1
          unless -f 'share/db/ohdsi.db';
          $convert->$method and ok( compare( $input->{$method}{out}, $tmp_file ) == 0, $method );
    }
}
