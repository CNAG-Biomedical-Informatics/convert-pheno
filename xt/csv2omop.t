#!/usr/bin/env perl
use strict;
use warnings;
use lib qw(./lib ../lib t/lib);

use Test::More;
use File::Spec;
use FindBin qw($Bin);
use Test::ConvertPheno
  qw(cli_script_path ensure_clean_dir remove_dir_if_exists has_ohdsi_db csv_files_match gunzip_file_content slurp_file);

my $cli = cli_script_path();
unless ( -x $cli ) {
    plan skip_all => "convert-pheno CLI not found at $cli";
}

unless ( has_ohdsi_db() ) {
    plan skip_all => "share/db/ohdsi.db is required for these tests";
}

my $infile      = File::Spec->catfile($Bin, '../t/csv2bff', 'in',  'csv_data.csv');
my $mapfile     = File::Spec->catfile($Bin, '../t/csv2bff', 'in',  'csv_mapping.yaml');
my $refdir      = File::Spec->catfile($Bin, '../t/csv2omop', 'out');
my $outdir      = File::Spec->catfile($refdir,     'tmp');
my $ref_prefix  = 'csv';

ensure_clean_dir($outdir);

my $cmd = join ' ',
    $cli,
    '-icsv',       $infile,
    '--oomop',
    '--out-dir',   $outdir,
    '--test',
    '--mapping-file', $mapfile,
    '--sep',       ',',
    '--ohdsi-db';
ok( system($cmd) == 0, "CLI ran without error" );

# The tables we expect from csv2omop
my @tables = qw(
  PERSON
  CONDITION_OCCURRENCE
  OBSERVATION
  DRUG_EXPOSURE
  MEASUREMENT
);

for my $tbl (@tables) {
    my $ref = File::Spec->catfile($refdir,     "${ref_prefix}_${tbl}.csv");
    my $got = File::Spec->catfile($outdir,     "${tbl}.csv");

    ok( -e $got, "$tbl: $got was generated" );
    ok( csv_files_match($ref, $got),
        "$tbl: $got matches $ref" );
}

remove_dir_if_exists($outdir);

my $gz_outdir = File::Spec->catfile($refdir, 'tmp-gz');

ensure_clean_dir($gz_outdir);

my @gz_name_args;
for my $tbl (@tables) {
    push @gz_name_args, '--out-name', "$tbl=$tbl.csv.gz";
}

my $gz_cmd = join ' ',
    $cli,
    '-icsv',       $infile,
    '--oomop',
    '--out-dir',   $gz_outdir,
    @gz_name_args,
    '--test',
    '--mapping-file', $mapfile,
    '--sep',       ',',
    '--ohdsi-db';
ok( system($gz_cmd) == 0, "CLI ran without error for gzipped OMOP output" );

for my $tbl (@tables) {
    my $ref = File::Spec->catfile($refdir, "${ref_prefix}_${tbl}.csv");
    my $got = File::Spec->catfile($gz_outdir, "${tbl}.csv.gz");

    ok( -e $got, "$tbl: $got was generated in gzipped mode" );
    is( gunzip_file_content($got), slurp_file($ref),
        "$tbl: $got matches $ref after gunzip" );
}

remove_dir_if_exists($gz_outdir);

done_testing();
