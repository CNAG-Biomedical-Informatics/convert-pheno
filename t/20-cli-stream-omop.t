#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Config;
use Test::More;
use File::Temp qw(tempfile);
use Test::ConvertPheno qw(
  cli_script_path
  temp_output_file
  test_tmpdir
  gunzip_file_content
  has_ohdsi_db
);

my $cli = cli_script_path();
plan skip_all => "convert-pheno CLI not found at $cli" unless -f $cli;
plan skip_all => 'Skipping CLI stream tests on ld architectures due to known issues'
  if $Config{archname} =~ /-ld\b/;

use constant IS_WINDOWS => ( $^O eq 'MSWin32' || $^O eq 'cygwin' ) ? 1 : 0;
my $tmpdir = test_tmpdir();

sub run_cli {
    my (@cmd) = @_;
    my ( $fh, undef ) = tempfile( DIR => $tmpdir, SUFFIX => '.cli.log', UNLINK => 1 );
    my $pid = fork();
    die 'fork failed' unless defined $pid;

    if ( $pid == 0 ) {
        open STDOUT, '>&', $fh or die "dup STDOUT failed: $!";
        open STDERR, '>&', $fh or die "dup STDERR failed: $!";
        exec @cmd or die "exec failed: $!";
    }

    waitpid( $pid, 0 );
    seek $fh, 0, 0;
    local $/;
    my $output = <$fh>;
    close $fh;

    return ( $? >> 8, $output );
}

{
  SKIP: {
        skip 'CLI file comparisons are unreliable on Windows', 2 if IS_WINDOWS;

        my $tmp_file = temp_output_file( suffix => '.json.gz', dir => $tmpdir );
        my @cmd = (
            $^X,
            $cli,
            '-iomop',
            't/omop2bff/in/gz/omop_cdm_eunomia.sql.gz',
            '-obff',          $tmp_file,
            '--stream',
            '--omop-tables',  'DRUG_EXPOSURE',
            '--max-lines-sql', 2700,
            '-O',
            '--test',
        );

        my ( $status, $output ) = run_cli(@cmd);
        diag($output) if $status != 0 && defined $output && length $output;
        is( $status, 0, 'CLI omop2bff stream SQL.gz exits successfully' );
        is(
            gunzip_file_content('t/omop2bff/out/individuals_drug_exposure.json.gz'),
            gunzip_file_content($tmp_file),
            'CLI omop2bff stream SQL.gz matches reference output',
        );
    }
}

{
  SKIP: {
        skip 'CLI file comparisons are unreliable on Windows', 2 if IS_WINDOWS;
        skip q{share/db/ohdsi.db is required for streamed CSV.gz OMOP CLI test}, 2
          unless has_ohdsi_db();

        my $tmp_file = temp_output_file( suffix => '.json.gz', dir => $tmpdir );
        my @cmd = (
            $^X,
            $cli,
            '-iomop',
            't/omop2bff/in/gz/PERSON.csv.gz',
            't/omop2bff/in/gz/CONCEPT.csv.gz',
            't/omop2bff/in/gz/DRUG_EXPOSURE.csv.gz',
            '-obff',          $tmp_file,
            '--stream',
            '--ohdsi-db',
            '--sep',          "\t",
            '--max-lines-sql', 2700,
            '-O',
            '--test',
        );

        my ( $status, $output ) = run_cli(@cmd);
        diag($output) if $status != 0 && defined $output && length $output;
        is( $status, 0, 'CLI omop2bff stream CSV.gz exits successfully' );
        is(
            gunzip_file_content('t/omop2bff/out/individuals_csv.json.gz'),
            gunzip_file_content($tmp_file),
            'CLI omop2bff stream CSV.gz matches reference output',
        );
    }
}

done_testing();
