#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Config;
use File::Spec;
use Test::More;
use File::Temp qw(tempfile);
use Test::ConvertPheno qw(
  cli_script_path
  temp_output_file
  structured_files_match
  csv_files_match
  gunzip_file_content
  slurp_file
  load_json_file
  write_json_file
  has_ohdsi_db
  test_tmpdir
);

my $cli = cli_script_path();
plan skip_all => "convert-pheno CLI not found at $cli" unless -f $cli;
plan skip_all => 'Skipping CLI regression tests on ld architectures due to known issues'
  if $Config{archname} =~ /-ld\b/;

use constant IS_WINDOWS => ( $^O eq 'MSWin32' || $^O eq 'cygwin' ) ? 1 : 0;
my $tmpdir = test_tmpdir();

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
        name     => 'pxf2bff_generic_io',
        cmd      => [ '-i', 'pxf', 't/pxf2bff/in/pxf.json', '-o', 'bff', '__OUT__' ],
        expected => 't/pxf2bff/out/individuals.json',
        suffix   => '.json',
        compare  => 'structured',
    },
    {
        name     => 'pxf2bff_biosamples',
        cmd      => [
            '-ipxf', 't/pxf2bff/in/pxf.json',
            '-obff',
            '--entities', 'biosamples',
            '--out-dir',  $tmpdir,
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
        name     => 'omop2bff_csv_plain',
        cmd      => [
            '-iomop',
            't/omop2bff/in/PERSON.csv',
            't/omop2bff/in/CONCEPT.csv',
            't/omop2bff/in/DRUG_EXPOSURE.csv',
            '-obff', '__OUT__',
        ],
        expected => 't/omop2bff/out/individuals_csv.json',
        suffix   => '.json',
        compare  => 'structured',
    },
    {
        name     => 'omop2bff_csv_plain_generic_io',
        cmd      => [
            '-i', 'omop',
            't/omop2bff/in/PERSON.csv',
            't/omop2bff/in/CONCEPT.csv',
            't/omop2bff/in/DRUG_EXPOSURE.csv',
            '-o', 'bff',
            '__OUT__',
        ],
        expected => 't/omop2bff/out/individuals_csv.json',
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
        name     => 'bff2csv_gzip',
        cmd      => [ '-ibff', 't/bff2pxf/in/individuals.json', '-ocsv', '__OUT__' ],
        expected => 't/bff2csv/out/individuals.csv',
        suffix   => '.csv.gz',
        compare  => 'gunzip_to_plain',
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
        name     => 'pxf2csv_gzip',
        cmd      => [ '-ipxf', 't/pxf2bff/in/pxf.json', '-ocsv', '__OUT__' ],
        expected => 't/pxf2csv/out/pxf.csv',
        suffix   => '.csv.gz',
        compare  => 'gunzip_to_plain',
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
    return slurp_file($expected) eq gunzip_file_content($actual)
      if $kind eq 'gunzip_to_plain';

    die "Unknown compare kind <$kind>";
}

sub run_cli {
    my (@cmd) = @_;
    my ( $fh, $log_file ) = tempfile( DIR => $tmpdir, SUFFIX => '.cli.log', UNLINK => 1 );
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

        my $tmp_file = temp_output_file( suffix => $case->{suffix}, dir => $tmpdir );
        my @cmd      = map { $_ eq '__OUT__' ? $tmp_file : $_ } @{ $case->{cmd} };
        unshift @cmd, $^X, $cli;
        push @cmd, '-O', '--test';

        my $actual_file = $case->{entity_output}
          ? File::Spec->catfile( $tmpdir, $case->{entity_output} )
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

SKIP: {
    skip 'CLI file comparisons are unreliable on Windows', 2 if IS_WINDOWS;

    my $tmp_file  = temp_output_file( suffix => '.json', dir => $tmpdir );
    my $input_file = temp_output_file( suffix => '.json', dir => $tmpdir );

    my $payload = {
        patient      => { id => 'openehr-patient-2' },
        compositions => [
            load_json_file('t/openehr2bff/in/gecco_personendaten.json'),
            load_json_file('t/openehr2bff/in/ips_canonical.json'),
            load_json_file('t/openehr2bff/in/laboratory_report.json'),
            load_json_file('t/openehr2bff/in/compo_corona.json'),
        ],
    };
    write_json_file( $input_file, $payload );

    my @cmd = ( $^X, $cli, '-iopenehr', $input_file, '-opxf', $tmp_file, '-O', '--test' );
    my ( $exit, $output ) = run_cli(@cmd);

    is( $exit, 0, 'CLI openehr2pxf exits successfully' )
      or diag $output;
    ok(
        structured_files_match( 't/openehr2pxf/out/pxf.json', $tmp_file ),
        'CLI openehr2pxf matches reference output'
    );
}

SKIP: {
    skip 'CLI file comparisons are unreliable on Windows', 2 if IS_WINDOWS;

    my $tmp_file = temp_output_file( suffix => '.json', dir => $tmpdir );
    my @cmd = (
        $^X, $cli,
        '-ibff', 't/bff2pxf/in/individuals.json',
        '-opxf', $tmp_file,
        '--default-vital-status', 'UNKNOWN_STATUS',
        '-O',
        '--test',
    );

    my ( $status, $output ) = run_cli(@cmd);
    diag($output) if $status != 0 && defined $output && length $output;
    is( $status, 0, 'CLI bff2pxf accepts --default-vital-status' );

    my $pxf = load_json_file($tmp_file);
    is(
        $pxf->[0]{subject}{vitalStatus}{status},
        'UNKNOWN_STATUS',
        'CLI bff2pxf applies the configured default vitalStatus when no source value is available',
    );
}

done_testing();
