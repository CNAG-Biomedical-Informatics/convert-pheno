#!/usr/bin/env perl
use strict;
use warnings;
use lib ( './lib', '../lib' );
use feature qw(say);
use Data::Dumper;
use Convert::Pheno;
use Test::More tests => 2;
use File::Compare;

use_ok('Convert::Pheno') or exit;

my $input = {
    omop2bff => {
        in_file  => undef,
        in_files => [
            't/omop2bff/in/CONCEPT.csv', 't/omop2bff/in/MEASUREMENT.csv',
            't/omop2bff/in/PERSON.csv'
        ],
        ohdsi_db => 1,
        out      => 't/omop2bff/out/ohdsi.json'
    }
};

for my $method ( sort keys %{$input} ) {
    my $convert = Convert::Pheno->new(
        {
            in_files    => $input->{$method}{in_files},
            in_textfile => 1,
            test        => 1,
            ohdsi_db    => $input->{$method}{'ohdsi_db'},
            method      => $method
        }
    );

  SKIP: {
        skip qq{because 'db/ohdsi.db' is required with <ohdsi_db>}, 1
          unless -f 'db/ohdsi.db';
        io_yaml_or_json(
            {
                filename => 't/test.json',
                data     => $convert->$method,
                mode     => 'write'
            }
          )
          and
          ok( compare( $input->{$method}{out}, 't/test.json' ) == 0, $method );
    }
}
