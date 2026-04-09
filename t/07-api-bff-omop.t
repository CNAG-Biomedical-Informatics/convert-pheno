#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use Test::ConvertPheno qw(build_convert has_ohdsi_db load_csv_table);

plan skip_all => 'share/db/ohdsi.db is required for bff2omop tests'
  unless has_ohdsi_db();

my $convert = build_convert(
    in_file   => 't/bff2omop/in/individuals.json',
    ohdsi_db  => 1,
    method    => 'bff2omop',
);

my $got = $convert->bff2omop;

my %expected = (
    PERSON               => load_csv_table('t/bff2omop/out/eunomia_PERSON.csv'),
    CONDITION_OCCURRENCE => load_csv_table('t/bff2omop/out/eunomia_CONDITION_OCCURRENCE.csv'),
    OBSERVATION          => load_csv_table('t/bff2omop/out/eunomia_OBSERVATION.csv'),
    PROCEDURE_OCCURRENCE => load_csv_table('t/bff2omop/out/eunomia_PROCEDURE_OCCURRENCE.csv'),
);

for my $table ( sort keys %expected ) {
    ok( exists $got->{$table}, "$table table is present" );
    my @headers = sort keys %{ $expected{$table}[0] };
    my @normalized = map {
        my $source = $_;
        my %row = map { $_ => ( exists $source->{$_} ? $source->{$_} : '' ) } @headers;
        \%row;
    } @{ $got->{$table} };
    is_deeply( \@normalized, $expected{$table}, "$table matches fixture" );
}

done_testing();
