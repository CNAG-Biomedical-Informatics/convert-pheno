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
my $infile     = 't/bff2omop/in/individuals.json';
my $refdir     = 't/bff2omop/out';
my $outdir     = 't/bff2omop/out/tmp';
my $ref_prefix = 'eunomia';
my $test_prefix= 'test';

# Clean and recreate tmp dir
remove_tree($outdir) if -d $outdir;
mkpath($outdir);

# Run the converter via CLI
my $cmd = join ' ',
    $cli,
    '-ibff',      $infile,
    '--oomop',    $test_prefix,
    '--out-dir',  $outdir,
    '--test',
    '--ohdsi-db';
ok( system($cmd) == 0, "CLI ran without error" );

# Now verify each of the six OMOP tables
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
    ok( compare($ref, $got) == 0, "$tbl: $got matches $ref" );
}

remove_tree($outdir) if -d $outdir;

done_testing();
