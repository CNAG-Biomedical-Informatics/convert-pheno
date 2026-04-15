#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use Test::ConvertPheno qw(cli_script_path);
use Convert::Pheno::CLI::Args qw(build_cli_request);

my $request = build_cli_request(
    argv => [
        '-icsv',          't/csv2bff/in/csv_data.csv',
        '--mapping-file', 't/csv2bff/in/csv_mapping.yaml',
        '-obff',          'individuals.json',
        '-u',             'alice',
    ],
    usage_error => sub { die @_ },
    schema_file => 'share/schema/mapping.json',
    out_dir     => '/tmp',
    color       => 1,
);

is(
    $request->{data}{username},
    'alice',
    'CLI parser accepts -u as an alias for --username'
);

$request = build_cli_request(
    argv => [
        '-ibff',                  't/bff2pxf/in/individuals.json',
        '-opxf',                  'phenopackets.json',
        '--default-vital-status', 'UNKNOWN_STATUS',
    ],
    usage_error => sub { die @_ },
    schema_file => 'share/schema/mapping.json',
    out_dir     => '/tmp',
    color       => 1,
);

is(
    $request->{data}{default_vital_status},
    'UNKNOWN_STATUS',
    'CLI parser accepts --default-vital-status for PXF output'
);

$request = build_cli_request(
    argv => [
        '-ipxf',     't/pxf2bff/in/pxf.json',
        '-obff',
        '--entities', 'biosamples',
        '--out-dir', '/tmp',
    ],
    usage_error => sub { die @_ },
    schema_file => 'share/schema/mapping.json',
    out_dir     => '.',
    color       => 1,
);

is(
    $request->{data}{method},
    'pxf2bff',
    'CLI parser keeps -obff as the explicit BFF selector in entity mode'
);

is_deeply(
    $request->{data}{entities},
    ['biosamples'],
    'CLI parser accepts -obff together with --entities'
);

my $usage_error;
eval {
    build_cli_request(
        argv => [
            '-ipxf',                  't/pxf2bff/in/pxf.json',
            '-obff',                  'individuals.json',
            '--default-vital-status', 'DECEASED',
        ],
        usage_error => sub { die @_ },
        schema_file => 'share/schema/mapping.json',
        out_dir     => '/tmp',
        color       => 1,
    );
    1;
} or $usage_error = $@;

like(
    $usage_error,
    qr/--default-vital-status> is only valid with PXF output/,
    'CLI parser rejects --default-vital-status without PXF output'
);

my $cli = cli_script_path();
plan skip_all => "convert-pheno CLI not found at $cli" unless -f $cli;

my $help = qx{$^X $cli --help 2>&1};
is( $? >> 8, 0, 'CLI help exits successfully' );
like( $help, qr/--search <type>/, 'CLI help documents --search' );
like(
    $help,
    qr/--min-text-similarity-score <s>/,
    'CLI help documents --min-text-similarity-score'
);
like(
    $help,
    qr/--text-similarity-method <m>/,
    'CLI help documents --text-similarity-method'
);
like(
    $help,
    qr/--levenshtein-weight <w>/,
    'CLI help documents --levenshtein-weight'
);
like(
    $help,
    qr/--username\|-u <name>/,
    'CLI help documents the restored username alias'
);
like(
    $help,
    qr/--default-vital-status <s>/,
    'CLI help documents --default-vital-status'
);
like(
    $help,
    qr/\[ALIVE\|DECEASED\|UNKNOWN_STATUS\]/,
    'CLI help documents supported vitalStatus fallback values'
);
like(
    $help,
    qr/Supported:\s+individuals,\s+biosamples,\s+datasets,\s+cohorts/s,
    'CLI help documents the supported BFF entities'
);
like(
    $help,
    qr/biosamples are emitted from -ipxf when present/s,
    'CLI help documents first-class biosample output from PXF'
);
like(
    $help,
    qr/datasets and\s+cohorts are synthesized from individuals/s,
    'CLI help documents synthesized dataset and cohort entities'
);
like(
    $help,
    qr/Use with -obff and --out-dir/s,
    'CLI help documents that entity mode keeps -obff explicit'
);
like(
    $help,
    qr/-obff FILE keeps the individuals-only BFF behavior\./s,
    'CLI help documents the individuals-only BFF behavior'
);
like(
    $help,
    qr/-obff --entities \.\.\. --out-dir DIR writes one file per requested BFF entity\./s,
    'CLI help documents the explicit entity-aware BFF form'
);

my $usage_error_output =
  qx{$^X $cli -ipxf t/pxf2bff/in/pxf.json --entities biosamples --out-dir /tmp 2>&1};
is( $? >> 8, 1, 'CLI validation error exits with status 1' );
like(
    $usage_error_output,
    qr/Error: .*select BFF output with <-obff>/s,
    'CLI validation error keeps the focused message'
);
like(
    $usage_error_output,
    qr/Run `convert-pheno --help` for full usage/,
    'CLI validation error points users to --help for the full reference'
);
unlike(
    $usage_error_output,
    qr/Common input flags:/,
    'CLI validation error no longer dumps the full help text'
);

done_testing();
