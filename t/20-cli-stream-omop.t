#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Config;
use Test::More;
use Test::ConvertPheno qw(
  cli_script_path
  temp_output_file
  test_tmpdir
  gunzip_file_content
  test_ohdsi_db_dir
  run_command_capture
);

my $cli = cli_script_path();
plan skip_all => "convert-pheno CLI not found at $cli" unless -f $cli;
plan skip_all => 'Skipping CLI stream tests on ld architectures due to known issues'
  if $Config{archname} =~ /-ld\b/;

my $tmpdir = test_tmpdir();
my $test_ohdsi_db_dir = test_ohdsi_db_dir();

sub run_cli {
    my (@cmd) = @_;
    my ( $status, $stdout, $stderr ) =
      run_command_capture( command => \@cmd );
    return ( $status, $stdout . $stderr );
}

{
    my $tmp_file = temp_output_file( suffix => '.json.gz', dir => $tmpdir );
    my @cmd = (
        $^X,
        $cli,
        '-iomop',
        't/omop2bff/in/gz/omop_cdm_eunomia.sql.gz',
        '-obff',           $tmp_file,
        '--stream',
        '--omop-tables',   'DRUG_EXPOSURE',
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

{
    my $tmp_file = temp_output_file( suffix => '.json.gz', dir => $tmpdir );
    my @cmd = (
        $^X,
        $cli,
        '-iomop',
        't/omop2bff/in/gz/PERSON.csv.gz',
        't/omop2bff/in/gz/CONCEPT.csv.gz',
        't/omop2bff/in/gz/DRUG_EXPOSURE.csv.gz',
        '-obff',                $tmp_file,
        '--stream',
        '--ohdsi-db',
        '--path-to-ohdsi-db',  $test_ohdsi_db_dir,
        '--sep',                "\t",
        '--max-lines-sql',      2700,
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

done_testing();
