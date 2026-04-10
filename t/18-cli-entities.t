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
    '--entities', 'individuals', 'biosamples',
    '--out-dir', $multi_out_dir,
    '--out-entity', 'biosamples=samples.json',
    '-O',
);

my $multi_status = system @multi_cmd;
is( $multi_status, 0, 'CLI accepts space-separated --entities values' );
ok( -f File::Spec->catfile( $multi_out_dir, 'individuals.json' ), 'CLI writes individuals.json in multi-entity mode' );
ok( -f File::Spec->catfile( $multi_out_dir, 'samples.json' ), 'CLI writes custom biosample file in multi-entity mode' );

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
        qr/When using <--entities>, please use <--out-dir> without <-obff FILE>/,
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

done_testing();
