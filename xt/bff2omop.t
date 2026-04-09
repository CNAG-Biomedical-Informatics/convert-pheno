#!/usr/bin/env perl

use strict;
use warnings;
use lib qw(./lib ../lib t/lib);

use Test::More;
use File::Spec;
use Test::ConvertPheno
  qw(cli_script_path ensure_clean_dir remove_dir_if_exists has_ohdsi_db csv_files_match);

my $cli = cli_script_path();
unless ( -x $cli ) {
    plan skip_all => "convert-pheno CLI not found at $cli";
}

unless ( has_ohdsi_db() ) {
    plan skip_all => "share/db/ohdsi.db is required for these tests";
}

my $infile     = 't/bff2omop/in/individuals.json';
my $refdir     = 't/bff2omop/out';
my $outdir     = 't/bff2omop/out/tmp';
my $ref_prefix = 'eunomia';
my $test_prefix = 'test';

ensure_clean_dir($outdir);

my $cmd = join ' ',
    $cli,
    '-ibff',      $infile,
    '--oomop',    $test_prefix,
    '--out-dir',  $outdir,
    '--test',
    '--ohdsi-db';
ok( system($cmd) == 0, "CLI ran without error" );

my @tables = qw(
  PERSON
  CONDITION_OCCURRENCE
  OBSERVATION
  PROCEDURE_OCCURRENCE
);

for my $tbl (@tables) {
    my $ref = File::Spec->catfile($refdir,     "${ref_prefix}_${tbl}.csv");
    my $got = File::Spec->catfile($outdir,     "${test_prefix}_${tbl}.csv");

    ok( -e $got, "$tbl: $got was generated" );
    ok( csv_files_match($ref, $got), "$tbl: $got matches $ref" );
}

remove_dir_if_exists($outdir);

done_testing();
