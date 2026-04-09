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
  structured_files_match
  csv_files_match
  gunzip_file_content
  has_ohdsi_db
);

my $cli = cli_script_path();
plan skip_all => "convert-pheno CLI not found at $cli" unless -f $cli;
plan skip_all => 'Skipping CLI regression tests on ld architectures due to known issues'
  if $Config{archname} =~ /-ld\b/;

use constant IS_WINDOWS => ( $^O eq 'MSWin32' || $^O eq 'cygwin' ) ? 1 : 0;

my @cases = (
    {
        name     => 'bff2pxf',
        cmd      => [ '-ibff', 't/bff2pxf/in/individuals.json', '-opxf', '__OUT__' ],
        expected => 't/bff2pxf/out/pxf.json',
        suffix   => '.json',
        compare  => 'structured',
    },
    {
        name     => 'pxf2bff',
        cmd      => [ '-ipxf', 't/pxf2bff/in/pxf.json', '-obff', '__OUT__' ],
        expected => 't/pxf2bff/out/individuals.json',
        suffix   => '.json',
        compare  => 'structured',
    },
    {
        name     => 'pxf2bff_biosamples',
        cmd      => [
            '-ipxf', 't/pxf2bff/in/pxf_biosamples.json',
            '--entities', 'biosamples',
            '--out-dir',  '/tmp',
        ],
        expected => 't/pxf2bff/out/biosamples.json',
        suffix   => '.json',
        compare  => 'structured',
        entity_output => 'biosamples.json',
    },
    {
        name     => 'redcap2bff',
        cmd      => [
            '-iredcap',            't/redcap2bff/in/redcap_data.csv',
            '--redcap-dictionary', 't/redcap2bff/in/redcap_dictionary.csv',
            '--mapping-file',      't/redcap2bff/in/redcap_mapping.yaml',
            '-obff',               '__OUT__',
        ],
        expected => 't/redcap2bff/out/individuals.json',
        suffix   => '.json',
        compare  => 'structured',
    },
    {
        name     => 'redcap2pxf',
        cmd      => [
            '-iredcap',            't/redcap2bff/in/redcap_data.csv',
            '--redcap-dictionary', 't/redcap2bff/in/redcap_dictionary.csv',
            '--mapping-file',      't/redcap2bff/in/redcap_mapping.yaml',
            '-opxf',               '__OUT__',
        ],
        expected => 't/redcap2pxf/out/pxf.json',
        suffix   => '.json',
        compare  => 'structured',
    },
    {
        name     => 'omop2bff',
        cmd      => [ '-iomop', 't/omop2bff/in/omop_cdm_eunomia.sql', '-obff', '__OUT__' ],
        expected => 't/omop2bff/out/individuals.json',
        suffix   => '.json',
        compare  => 'structured',
    },
    {
        name     => 'omop2pxf',
        cmd      => [ '-iomop', 't/omop2bff/in/omop_cdm_eunomia.sql', '-opxf', '__OUT__' ],
        expected => 't/omop2pxf/out/pxf.json',
        suffix   => '.json',
        compare  => 'structured',
    },
    {
        name     => 'cdisc2bff',
        cmd      => [
            '-icdisc',             't/cdisc2bff/in/cdisc_odm_data.xml',
            '--redcap-dictionary', 't/redcap2bff/in/redcap_dictionary.csv',
            '--mapping-file',      't/redcap2bff/in/redcap_mapping.yaml',
            '-obff',               '__OUT__',
        ],
        expected => 't/cdisc2bff/out/individuals.json',
        suffix   => '.json',
        compare  => 'structured',
    },
    {
        name     => 'cdisc2pxf',
        cmd      => [
            '-icdisc',             't/cdisc2bff/in/cdisc_odm_data.xml',
            '--redcap-dictionary', 't/redcap2bff/in/redcap_dictionary.csv',
            '--mapping-file',      't/redcap2bff/in/redcap_mapping.yaml',
            '-opxf',               '__OUT__',
        ],
        expected => 't/cdisc2pxf/out/pxf.json',
        suffix   => '.json',
        compare  => 'structured',
    },
    {
        name     => 'bff2csv',
        cmd      => [ '-ibff', 't/bff2pxf/in/individuals.json', '-ocsv', '__OUT__' ],
        expected => 't/bff2csv/out/individuals.csv',
        suffix   => '.csv',
        compare  => 'csv',
    },
    {
        name     => 'bff2jsonf',
        cmd      => [ '-ibff', 't/bff2pxf/in/individuals.json', '-ojsonf', '__OUT__' ],
        expected => 't/bff2jsonf/out/individuals.fold.json',
        suffix   => '.json',
        compare  => 'structured',
    },
    {
        name     => 'pxf2csv',
        cmd      => [ '-ipxf', 't/pxf2bff/in/pxf.json', '-ocsv', '__OUT__' ],
        expected => 't/pxf2csv/out/pxf.csv',
        suffix   => '.csv',
        compare  => 'csv',
    },
    {
        name     => 'pxf2jsonf',
        cmd      => [ '-ipxf', 't/pxf2bff/in/pxf.json', '-ojsonf', '__OUT__' ],
        expected => 't/pxf2jsonf/out/pxf.fold.json',
        suffix   => '.json',
        compare  => 'structured',
    },
    {
        name     => 'csv2bff',
        cmd      => [
            '-icsv',          't/csv2bff/in/csv_data.csv',
            '--mapping-file', 't/csv2bff/in/csv_mapping.yaml',
            '--sep',          ',',
            '-obff',          '__OUT__',
        ],
        expected => 't/csv2bff/out/individuals.json',
        suffix   => '.json',
        compare  => 'structured',
    },
    {
        name     => 'csv2pxf',
        cmd      => [
            '-icsv',          't/csv2bff/in/csv_data.csv',
            '--mapping-file', 't/csv2bff/in/csv_mapping.yaml',
            '--sep',          ',',
            '-opxf',          '__OUT__',
        ],
        expected => 't/csv2pxf/out/pxf.json',
        suffix   => '.json',
        compare  => 'structured',
    },
);

sub compare_case_output {
    my ( $kind, $expected, $actual ) = @_;

    return structured_files_match( $expected, $actual ) if $kind eq 'structured';
    return csv_files_match( $expected, $actual )         if $kind eq 'csv';
    return gunzip_file_content($expected) eq gunzip_file_content($actual)
      if $kind eq 'gunzip';

    die "Unknown compare kind <$kind>";
}

sub run_cli {
    my (@cmd) = @_;
    my ( $fh, $log_file ) = tempfile( DIR => '/tmp', SUFFIX => '.cli.log', UNLINK => 1 );
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

for my $case (@cases) {
  SKIP: {
        skip 'CLI file comparisons are unreliable on Windows', 2 if IS_WINDOWS;
        skip q{share/db/ohdsi.db is required for this CLI OMOP test}, 2
          if $case->{requires_db} && !has_ohdsi_db();

        my $tmp_file = temp_output_file( suffix => $case->{suffix}, dir => '/tmp' );
        my @cmd      = map { $_ eq '__OUT__' ? $tmp_file : $_ } @{ $case->{cmd} };
        unshift @cmd, $^X, $cli;
        push @cmd, '-O', '--test';

        my $actual_file = $case->{entity_output}
          ? "/tmp/$case->{entity_output}"
          : $tmp_file;

        my ( $status, $output ) = run_cli(@cmd);
        diag($output) if $status != 0 && defined $output && length $output;
        is( $status, 0, "CLI $case->{name} exits successfully" );
        ok(
            compare_case_output( $case->{compare}, $case->{expected}, $actual_file ),
            "CLI $case->{name} matches reference output",
        );
    }
}

done_testing();
