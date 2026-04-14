#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use File::Spec;
use File::Temp qw(tempfile);
use Test::ConvertPheno qw(
  cli_script_path
  ensure_clean_dir
  remove_dir_if_exists
  load_data_file
  load_json_file
  write_json_file
);

my $cli = cli_script_path();
plan skip_all => "convert-pheno CLI not found at $cli" unless -f $cli;

my $out_dir = ensure_clean_dir('t/cli-entities-out');
my $input_file = File::Spec->catfile( $out_dir, 'pxf-biosamples.json' );

write_json_file(
    $input_file,
    [
        {
            subject    => { id => 'subject-1', sex => 'MALE' },
            biosamples => [
                { id => 'bio-1' },
                { id => 'bio-2', individualId => 'subject-1' },
            ],
        },
    ]
);

my @cmd = (
    $^X,
    $cli,
    '-ipxf', $input_file,
    '-obff',
    '--entities', 'biosamples',
    '--out-dir', $out_dir,
    '-O',
);

my $status = system @cmd;
is( $status, 0, 'CLI exits successfully for biosample entity output' );

my $biosamples_file = File::Spec->catfile( $out_dir, 'biosamples.json' );
ok( -f $biosamples_file, 'CLI writes biosamples.json by default for biosample-only output' );

my $biosamples = load_json_file($biosamples_file);
ok( ref($biosamples) eq 'ARRAY', 'biosamples output is a JSON array' );
ok( @$biosamples > 0, 'biosamples output is not empty' );
ok( exists $biosamples->[0]{id}, 'biosamples output keeps biosample ids' );
is( $biosamples->[0]{individualId}, 'subject-1', 'CLI fills in individualId when missing' );

my $custom_out_dir = ensure_clean_dir('t/cli-entities-custom-out');
my @custom_cmd = (
    $^X,
    $cli,
    '-ipxf', $input_file,
    '-obff',
    '--entities', 'biosamples',
    '--out-dir', $custom_out_dir,
    '--out-entity', 'biosamples=samples.json',
    '-O',
);

my $custom_status = system @custom_cmd;
is( $custom_status, 0, 'CLI accepts custom per-entity output filename' );

my $custom_biosamples_file = File::Spec->catfile( $custom_out_dir, 'samples.json' );
ok( -f $custom_biosamples_file, 'CLI writes custom biosample filename when requested' );
ok( !-f File::Spec->catfile( $custom_out_dir, 'biosamples.json' ), 'CLI does not also write the default biosamples filename when overridden' );

my $multi_out_dir = ensure_clean_dir('t/cli-entities-multi-out');
my @multi_cmd = (
    $^X,
    $cli,
    '-ipxf', $input_file,
    '-obff',
    '--entities', 'individuals', 'biosamples',
    '--out-dir', $multi_out_dir,
    '--out-entity', 'biosamples=samples.json',
    '-O',
);

my $multi_status = system @multi_cmd;
is( $multi_status, 0, 'CLI accepts space-separated --entities values' );
ok( -f File::Spec->catfile( $multi_out_dir, 'individuals.json' ), 'CLI writes individuals.json in multi-entity mode' );
ok( -f File::Spec->catfile( $multi_out_dir, 'samples.json' ), 'CLI writes custom biosample file in multi-entity mode' );

my $derived_out_dir = ensure_clean_dir('t/cli-entities-derived-out');
my @derived_cmd = (
    $^X,
    $cli,
    '-ipxf', $input_file,
    '-obff',
    '--entities', 'datasets', 'cohorts',
    '--out-dir', $derived_out_dir,
    '-O',
    '--test',
);

my $derived_status = system @derived_cmd;
is( $derived_status, 0, 'CLI synthesizes datasets and cohorts from individuals' );

my $datasets_file = File::Spec->catfile( $derived_out_dir, 'datasets.json' );
my $cohorts_file  = File::Spec->catfile( $derived_out_dir, 'cohorts.json' );
ok( -f $datasets_file, 'CLI writes datasets.json in derived-entity mode' );
ok( -f $cohorts_file, 'CLI writes cohorts.json in derived-entity mode' );

my $datasets = load_json_file($datasets_file);
my $cohorts  = load_json_file($cohorts_file);
is( $datasets->[0]{id}, 'dataset-1', 'datasets output includes a synthesized dataset id' );
is( $datasets->[0]{info}{individualCount}, 1, 'datasets output records the individual count' );
is( $cohorts->[0]{id}, 'cohort-1', 'cohorts output includes a synthesized cohort id' );
is( $cohorts->[0]{cohortType}, 'study-defined', 'cohorts output defaults to study-defined' );
is( $cohorts->[0]{cohortSize}, 1, 'cohorts output records the cohort size' );

{
    my $entity_mapping = load_data_file('t/csv2bff/in/csv_mapping.yaml');
    my $mapping = {
        project => delete $entity_mapping->{project},
        beacon  => {
            individuals => $entity_mapping->{beacon}{individuals},
            datasets    => {
                id          => 'dataset-from-yaml',
                name        => 'Dataset From YAML',
                externalUrl => 'https://example.org/datasets/csv-demo',
                info        => {
                    projectCode => 'CSV-DEMO',
                },
            },
            cohorts => {
                id              => 'cohort-from-yaml',
                name            => 'Cohort From YAML',
                cohortType      => 'beacon-defined',
                cohortDataTypes => [
                    {
                        id    => 'OMIABIS:0000060',
                        label => 'survey data',
                    },
                ],
            },
        },
    };

    my ( $fh, $mapping_file ) = tempfile( DIR => '/tmp', SUFFIX => '.json', UNLINK => 1 );
    close $fh;
    write_json_file( $mapping_file, $mapping );

    my $mapping_out_dir = ensure_clean_dir('t/cli-entities-mapping-out');
    my @mapping_cmd = (
        $^X,
        $cli,
        '-icsv', 't/csv2bff/in/csv_data.csv',
        '--mapping-file', $mapping_file,
        '--sep', ',',
        '-obff',
        '--entities', 'datasets', 'cohorts',
        '--out-dir', $mapping_out_dir,
        '-O',
        '--test',
    );

    my $mapping_status = system @mapping_cmd;
    is( $mapping_status, 0, 'CLI accepts beacon metadata overrides from the mapping file' );

    my $yaml_datasets = load_json_file( File::Spec->catfile( $mapping_out_dir, 'datasets.json' ) );
    my $yaml_cohorts  = load_json_file( File::Spec->catfile( $mapping_out_dir, 'cohorts.json' ) );

    is( $yaml_datasets->[0]{id}, 'dataset-from-yaml', 'mapping file overrides the synthesized dataset id' );
    is( $yaml_datasets->[0]{name}, 'Dataset From YAML', 'mapping file overrides the synthesized dataset name' );
    is( $yaml_datasets->[0]{externalUrl}, 'https://example.org/datasets/csv-demo', 'mapping file adds dataset metadata fields' );
    is( $yaml_datasets->[0]{info}{projectCode}, 'CSV-DEMO', 'mapping file merges custom dataset info' );
    ok( exists $yaml_datasets->[0]{info}{individualCount}, 'mapping file keeps generated dataset counts' );

    is( $yaml_cohorts->[0]{id}, 'cohort-from-yaml', 'mapping file overrides the synthesized cohort id' );
    is( $yaml_cohorts->[0]{cohortType}, 'beacon-defined', 'mapping file overrides cohortType' );
    is( $yaml_cohorts->[0]{cohortDataTypes}[0]{id}, 'OMIABIS:0000060', 'mapping file overrides inferred cohort data types' );

    remove_dir_if_exists($mapping_out_dir);
}

{
    my $legacy_out_dir = ensure_clean_dir('t/cli-entities-legacy-out');
    my $legacy_out_file = File::Spec->catfile( $legacy_out_dir, 'individuals.json' );
    my ( $fh, $log_file ) =
      tempfile( DIR => '/tmp', SUFFIX => '.cli.log', UNLINK => 1 );
    my $pid = fork();
    die 'fork failed' unless defined $pid;

    if ( $pid == 0 ) {
        open STDOUT, '>&', $fh or die "dup STDOUT failed: $!";
        open STDERR, '>&', $fh or die "dup STDERR failed: $!";
        exec(
            $^X,
            $cli,
            '-ipxf', $input_file,
            '-obff', $legacy_out_file,
            '-O',
        ) or die "exec failed: $!";
    }

    waitpid( $pid, 0 );
    seek $fh, 0, 0;
    local $/;
    my $output = <$fh>;
    close $fh;

    is( $? >> 8, 0, 'CLI keeps legacy pxf2bff single-output mode working when biosamples are present' );
    like(
        $output,
        qr/Warning: input PXF contains biosamples\./,
        'CLI warns when legacy pxf2bff output hides first-class biosamples'
    );
    ok( -f $legacy_out_file, 'CLI still writes the legacy individuals output file' );

    my $legacy_individuals = load_json_file($legacy_out_file);
    is(
        $legacy_individuals->[0]{info}{phenopacket}{biosamples}[0]{id},
        'bio-1',
        'legacy pxf2bff output still preserves biosamples under info.phenopacket.biosamples'
    );

    remove_dir_if_exists($legacy_out_dir);
}

{
    my ( $fh, $log_file ) =
      tempfile( DIR => '/tmp', SUFFIX => '.cli.log', UNLINK => 1 );
    my $pid = fork();
    die 'fork failed' unless defined $pid;

    if ( $pid == 0 ) {
        open STDOUT, '>&', $fh or die "dup STDOUT failed: $!";
        open STDERR, '>&', $fh or die "dup STDERR failed: $!";
        exec(
            $^X,
            $cli,
            '-ipxf', $input_file,
            '--entities', 'individuals,biosamples',
            '--out-dir', $out_dir,
        ) or die "exec failed: $!";
    }

    waitpid( $pid, 0 );
    seek $fh, 0, 0;
    local $/;
    my $output = <$fh>;
    close $fh;

    isnt( $? >> 8, 0, 'CLI rejects comma-separated --entities values' );
    like(
        $output,
        qr/Please provide <--entities> as a space-separated list/,
        'CLI prints a focused error for comma-separated --entities'
    );
}

{
    my ( $fh, $log_file ) =
      tempfile( DIR => '/tmp', SUFFIX => '.cli.log', UNLINK => 1 );
    my $pid = fork();
    die 'fork failed' unless defined $pid;

    if ( $pid == 0 ) {
        open STDOUT, '>&', $fh or die "dup STDOUT failed: $!";
        open STDERR, '>&', $fh or die "dup STDERR failed: $!";
        exec(
            $^X,
            $cli,
            '-ipxf', $input_file,
            '-obff', 'should-not-work.json',
            '--entities', 'biosamples'
        ) or die "exec failed: $!";
    }

    waitpid( $pid, 0 );
    seek $fh, 0, 0;
    local $/;
    my $output = <$fh>;
    close $fh;

    isnt( $? >> 8, 0, 'CLI rejects -obff FILE together with --entities' );
    like(
        $output,
        qr/please omit the file and use <-obff --entities \.\.\. --out-dir DIR>/,
        'CLI prints a focused error for --entities with -obff FILE'
    );
}

{
    my ( $fh, $log_file ) =
      tempfile( DIR => '/tmp', SUFFIX => '.cli.log', UNLINK => 1 );
    my $pid = fork();
    die 'fork failed' unless defined $pid;

    if ( $pid == 0 ) {
        open STDOUT, '>&', $fh or die "dup STDOUT failed: $!";
        open STDERR, '>&', $fh or die "dup STDERR failed: $!";
        exec(
            $^X,
            $cli,
            '-ipxf', $input_file,
            '--entities', 'biosamples',
            '--out-dir', $out_dir,
        ) or die "exec failed: $!";
    }

    waitpid( $pid, 0 );
    seek $fh, 0, 0;
    local $/;
    my $output = <$fh>;
    close $fh;

    isnt( $? >> 8, 0, 'CLI rejects --entities without selecting BFF output' );
    like(
        $output,
        qr/select BFF output with <-obff>/,
        'CLI explains that entity mode still requires -obff'
    );
}

{
    my ( $fh, $log_file ) =
      tempfile( DIR => '/tmp', SUFFIX => '.cli.log', UNLINK => 1 );
    my $pid = fork();
    die 'fork failed' unless defined $pid;

    if ( $pid == 0 ) {
        open STDOUT, '>&', $fh or die "dup STDOUT failed: $!";
        open STDERR, '>&', $fh or die "dup STDERR failed: $!";
        exec(
            $^X,
            $cli,
            '-ipxf', $input_file,
            '--out-entity', 'biosamples=samples.json'
        ) or die "exec failed: $!";
    }

    waitpid( $pid, 0 );
    seek $fh, 0, 0;
    local $/;
    my $output = <$fh>;
    close $fh;

    isnt( $? >> 8, 0, 'CLI rejects --out-entity without --entities' );
    like(
        $output,
        qr/The flag <--out-entity> requires <--entities>/,
        'CLI prints a focused error for --out-entity without --entities'
    );
}

remove_dir_if_exists($out_dir);
remove_dir_if_exists($custom_out_dir);
remove_dir_if_exists($multi_out_dir);
remove_dir_if_exists($derived_out_dir);

done_testing();
