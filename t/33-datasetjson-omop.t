#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use Test::ConvertPheno qw(build_convert load_csv_table test_ohdsi_db_dir);

my @files = sort glob 't/datasetjson2bff/in/*.json';
my $convert = build_convert(
    in_files => \@files,
    ohdsi_db => 1,
    path_to_ohdsi_db => test_ohdsi_db_dir(),
    method   => 'datasetjson2omop',
);

my $got = $convert->datasetjson2omop;
my @tables = qw(
  CONDITION_OCCURRENCE
  DRUG_EXPOSURE
  MEASUREMENT
  OBSERVATION
  PERSON
  PROCEDURE_OCCURRENCE
);

for my $table (@tables) {
    my $expected = load_csv_table("t/datasetjson2omop/out/$table.csv");
    ok( exists $got->{$table}, "$table table is present" );

    my @headers = sort keys %{ $expected->[0] };
    my @normalized = map {
        my $source = $_;
        my %row = map {
            $_ => ( exists $source->{$_} ? $source->{$_} : q{} )
        } @headers;
        \%row;
    } @{ $got->{$table} };

    is_deeply( \@normalized, $expected, "$table matches the validated fixture" );
}

done_testing();
