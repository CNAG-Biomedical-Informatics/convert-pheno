#!/usr/bin/env perl
use strict;
use warnings;
use lib qw(./lib ../lib t/lib);

use Test::More;
use Test::ConvertPheno
  qw(build_convert has_ohdsi_db temp_output_file structured_files_match);

plan skip_all => "share/db/ohdsi.db is required for these tests"
  unless has_ohdsi_db();

my $tmp_file = temp_output_file();
my $convert  = build_convert(
    in_files => [
        't/omop2bff/in/CONCEPT.csv',
        't/omop2bff/in/DRUG_EXPOSURE.csv',
        't/omop2bff/in/PERSON.csv',
    ],
    out_file => $tmp_file,
    ohdsi_db => 1,
    method   => 'omop2bff',
);

ok( $convert->omop2bff, 'omop2bff runs with OHDSI db' );
ok(
    structured_files_match( 't/omop2bff/out/ohdsi.json', $tmp_file ),
    'omop2bff with OHDSI db matches reduced fixture'
);

done_testing();
