#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use File::Spec;
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

remove_dir_if_exists($out_dir);

done_testing();
