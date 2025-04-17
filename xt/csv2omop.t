#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Compare qw(compare);
use File::Spec;
use File::Path qw(remove_tree mkpath);
use FindBin qw($Bin);

# Locate the CLI script
my $cli = File::Spec->catfile($Bin, '..', 'bin', 'convert-pheno');
unless ( -x $cli ) {
    plan skip_all => "convert-pheno CLI not found at $cli";
}

# Skip everything if the OHDSI DB isn’t there
unless ( -f 'share/db/ohdsi.db' ) {
    plan skip_all => "share/db/ohdsi.db is required for these tests";
}

# Prepare paths
my $infile      = File::Spec->catfile($Bin, '../t/csv2bff', 'in',  'csv_data.csv');
my $mapfile     = File::Spec->catfile($Bin, '../t/csv2bff', 'in',  'csv_mapping.yaml');
my $refdir      = File::Spec->catfile($Bin, '../t/csv2omop', 'out');
my $outdir      = File::Spec->catfile($refdir,     'tmp');
my $ref_prefix  = 'csv';
my $test_prefix = 'test';

# Clean and recreate tmp dir
remove_tree($outdir) if -d $outdir;
mkpath($outdir);

# Run the converter via CLI
my $cmd = join ' ',
    $cli,
    '-icsv',       $infile,
    '--oomop',     $test_prefix,
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
    my $got = File::Spec->catfile($outdir,     "${test_prefix}_${tbl}.csv");

    ok( -e $got, "$tbl: $got was generated" );
    ok( compare($ref, $got) == 0,
        "$tbl: $got matches $ref" );
}

# Clean up
remove_tree($outdir) if -d $outdir;

done_testing();
