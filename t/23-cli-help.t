#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use File::Spec;
use Test::More;
use Test::ConvertPheno qw(cli_script_path test_tmpdir);
use Convert::Pheno::CLI::Args qw(build_cli_request);

my $tmpdir = test_tmpdir();

my $request = build_cli_request(
    argv => [
        '-icsv',          't/csv2bff/in/csv_data.csv',
        '--mapping-file', 't/csv2bff/in/csv_mapping.yaml',
        '-obff',          'individuals.json',
        '-u',             'alice',
    ],
    usage_error => sub { die @_ },
    schema_file => 'share/schema/mapping-v2.json',
    out_dir     => $tmpdir,
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
    schema_file => 'share/schema/mapping-v2.json',
    out_dir     => $tmpdir,
    color       => 1,
);

is(
    $request->{data}{default_vital_status},
    'UNKNOWN_STATUS',
    'CLI parser accepts --default-vital-status for PXF output'
);

$request = build_cli_request(
    argv => [
        '-iomop', 't/omop2bff/in/omop_cdm_eunomia.sql',
        '-obff',  'individuals.json',
        '--no-source-info',
    ],
    usage_error => sub { die @_ },
    schema_file => 'share/schema/mapping-v2.json',
    out_dir     => $tmpdir,
    color       => 1,
);

is(
    $request->{data}{source_info},
    0,
    'CLI parser accepts --no-source-info'
);

$request = build_cli_request(
    argv => [
        '-ipxf',     't/pxf2bff/in/pxf.json',
        '-obff',
        '--entities', 'biosamples',
        '--out-dir', $tmpdir,
    ],
    usage_error => sub { die @_ },
    schema_file => 'share/schema/mapping-v2.json',
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

$request = build_cli_request(
    argv => [
        '-ibff', 't/bff2pxf/in/individuals.json',
        '-oomop',
        '--out-dir', $tmpdir,
        '--out-name', 'PERSON=patients.csv',
        '--ohdsi-db',
    ],
    usage_error => sub { die @_ },
    schema_file => 'share/schema/mapping-v2.json',
    out_dir     => '.',
    color       => 1,
);

is(
    $request->{data}{method},
    'bff2omop',
    'CLI parser accepts -oomop without a prefix value'
);

is(
    $request->{data}{output_name_overrides}{PERSON},
    File::Spec->catfile( $tmpdir, 'patients.csv' ),
    'CLI parser accepts --out-name for OMOP table output'
);

$request = build_cli_request(
    argv => [
        '-i', 'bff',
        't/bff2pxf/in/individuals.json',
        '-o', 'omop',
        '--out-dir', $tmpdir,
        '--ohdsi-db',
    ],
    usage_error => sub { die @_ },
    schema_file => 'share/schema/mapping-v2.json',
    out_dir     => '.',
    color       => 1,
);

is(
    $request->{data}{method},
    'bff2omop',
    'CLI parser accepts generic -o omop without an output prefix'
);

my @datasetjson_files = sort glob 't/datasetjson2bff/in/*.json';
$request = build_cli_request(
    argv => [
        '-i', 'dataset-json',
        @datasetjson_files,
        '--define-xml', 't/datasetxml2bff/in/define.xml',
        '-o', 'pxf',
        'phenopackets.json',
    ],
    usage_error => sub { die @_ },
    schema_file => 'share/schema/mapping-v2.json',
    out_dir     => $tmpdir,
    color       => 1,
);

is( $request->{data}{method}, 'datasetjson2pxf', 'CLI parser accepts Dataset-JSON input' );
is_deeply(
    $request->{data}{in_files},
    \@datasetjson_files,
    'CLI parser retains every Dataset-JSON domain file'
);
is(
    $request->{data}{define_xml},
    't/datasetxml2bff/in/define.xml',
    'CLI parser accepts optional Define-XML metadata with Dataset-JSON'
);

$request = build_cli_request(
    argv => [
        '-idataset-json', @datasetjson_files,
        '-oomop',
        '--out-dir', $tmpdir,
        '--ohdsi-db',
    ],
    usage_error => sub { die @_ },
    schema_file => 'share/schema/mapping-v2.json',
    out_dir     => '.',
    color       => 1,
);

is(
    $request->{data}{method},
    'datasetjson2omop',
    'CLI parser accepts Dataset-JSON to OMOP output'
);

my @datasetxml_files = map { "t/datasetxml2bff/in/$_.xml" } qw(dm mh lb ts);
$request = build_cli_request(
    argv => [
        '-i', 'dataset-xml',
        @datasetxml_files,
        '--define-xml', 't/datasetxml2bff/in/define.xml',
        '-o', 'pxf',
        'phenopackets.json',
    ],
    usage_error => sub { die @_ },
    schema_file => 'share/schema/mapping-v2.json',
    out_dir     => $tmpdir,
    color       => 1,
);

is( $request->{data}{method}, 'datasetxml2pxf', 'CLI parser accepts Dataset-XML input' );
is_deeply(
    $request->{data}{in_files},
    \@datasetxml_files,
    'CLI parser retains every Dataset-XML domain file'
);
is(
    $request->{data}{define_xml},
    't/datasetxml2bff/in/define.xml',
    'CLI parser retains the accompanying Define-XML file'
);

$request = build_cli_request(
    argv => [
        '-i', 'fhir',
        't/fhir2bff/in/patient-bundle.json',
        '-o', 'pxf',
        'phenopacket.json',
    ],
    usage_error => sub { die @_ },
    schema_file => 'share/schema/mapping-v2.json',
    out_dir     => $tmpdir,
    color       => 1,
);

is( $request->{data}{method}, 'fhir2pxf', 'CLI parser accepts generic FHIR input' );
is_deeply(
    $request->{data}{in_files},
    ['t/fhir2bff/in/patient-bundle.json'],
    'CLI parser retains FHIR Bundle files'
);

$request = build_cli_request(
    argv => [
        '-i', 'cbioportal',
        't/cbioportal2bff/in/acyc_mgh_2016',
        '-o', 'pxf',
        'phenopackets.json',
    ],
    usage_error => sub { die @_ },
    schema_file => 'share/schema/mapping-v2.json',
    out_dir     => $tmpdir,
    color       => 1,
);

is( $request->{data}{method}, 'cbioportal2pxf', 'CLI parser accepts generic cBioPortal input' );
is(
    $request->{data}{in_file},
    't/cbioportal2bff/in/acyc_mgh_2016',
    'CLI parser retains the cBioPortal study path'
);

$request = build_cli_request(
    argv => [
        '-ifhir', 't/fhir2bff/in/patient-bundle.json',
        '-obff',
        '--entities', 'biosamples',
        '--out-dir', $tmpdir,
    ],
    usage_error => sub { die @_ },
    schema_file => 'share/schema/mapping-v2.json',
    out_dir     => '.',
    color       => 1,
);

is( $request->{data}{method}, 'fhir2bff', 'CLI parser accepts compact FHIR input' );
is_deeply(
    $request->{data}{entities},
    ['biosamples'],
    'CLI parser accepts FHIR biosample output'
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
        schema_file => 'share/schema/mapping-v2.json',
        out_dir     => $tmpdir,
        color       => 1,
    );
    1;
} or $usage_error = $@;

like(
    $usage_error,
    qr/--default-vital-status> is only valid with PXF output/,
    'CLI parser rejects --default-vital-status without PXF output'
);

$usage_error = undef;
eval {
    build_cli_request(
        argv => [
            '-ibff', 't/bff2pxf/in/individuals.json',
            '-oomop', 'old-prefix',
            '--out-dir', $tmpdir,
            '--ohdsi-db',
        ],
        usage_error => sub { die @_ },
        schema_file => 'share/schema/mapping-v2.json',
        out_dir     => '.',
        color       => 1,
    );
    1;
} or $usage_error = $@;

like(
    $usage_error,
    qr/no longer accepts a prefix/,
    'CLI parser prints a focused error for the removed -oomop PREFIX form'
);

$usage_error = undef;
eval {
    build_cli_request(
        argv => [
            '-ibff', 't/bff2pxf/in/individuals.json',
            '-obff', 'individuals.json',
        ],
        usage_error => sub { die @_ },
        schema_file => 'share/schema/mapping-v2.json',
        out_dir     => $tmpdir,
        color       => 1,
    );
    1;
} or $usage_error = $@;

like(
    $usage_error,
    qr/Unsupported conversion <bff2bff>/,
    'CLI parser rejects unsupported same-format routes'
);

$usage_error = undef;
eval {
    build_cli_request(
        argv => [
            '-icbioportal', 'missing-study.zip',
            '-opxf', 'phenopackets.json',
        ],
        usage_error => sub { die @_ },
        schema_file => 'share/schema/mapping-v2.json',
        out_dir     => $tmpdir,
        color       => 1,
    );
    1;
} or $usage_error = $@;

like(
    $usage_error,
    qr/valid cBioPortal study directory or ZIP file/,
    'CLI parser reports the cBioPortal package requirement'
);

$usage_error = undef;
eval {
    build_cli_request(
        argv => [
            '-idataset-xml', @datasetxml_files,
            '-obff', 'individuals.json',
        ],
        usage_error => sub { die @_ },
        schema_file => 'share/schema/mapping-v2.json',
        out_dir     => $tmpdir,
        color       => 1,
    );
    1;
} or $usage_error = $@;

like(
    $usage_error,
    qr/accompanying Define-XML file with --define-xml/,
    'CLI parser requires Define-XML with Dataset-XML input'
);

my $cli = cli_script_path();
plan skip_all => "convert-pheno CLI not found at $cli" unless -f $cli;

my $help = qx{$^X $cli --help 2>&1};
is( $? >> 8, 0, 'CLI help exits successfully' );
my @help_contract = (
    [ like => qr/--search <type>/, 'CLI help documents --search' ],
    [ like => qr/--min-text-similarity-score <s>/, 'CLI help documents --min-text-similarity-score' ],
    [ like => qr/--text-similarity-method <m>/, 'CLI help documents --text-similarity-method' ],
    [ like => qr/--levenshtein-weight <w>/, 'CLI help documents --levenshtein-weight' ],
    [ like => qr/--term-audit-tsv <file>/, 'CLI help documents --term-audit-tsv' ],
    [ unlike => qr/--search-audit-tsv/, 'CLI help omits the replaced --search-audit-tsv option' ],
    [ unlike => qr/--print-hidden-labels/, 'CLI help omits the removed hidden-label option' ],
    [ like => qr/--username\|-u <name>/, 'CLI help documents the restored username alias' ],
    [ like => qr/--default-vital-status <s>/, 'CLI help documents --default-vital-status' ],
    [ like => qr/--source-info\|--no-source-info/, 'CLI help documents --no-source-info' ],
    [ like => qr/--stream\|--no-stream/, 'CLI help documents --no-stream' ],
    [ like => qr/--log \[file\]/, 'CLI help documents --log' ],
    [ like => qr/--color\|--no-color/, 'CLI help documents --no-color' ],
    [ like => qr/-icdisc-odm <file>/, 'CLI help names CDISC-ODM explicitly' ],
    [ like => qr/-icbioportal <path>/, 'CLI help documents cBioPortal study input' ],
    [ unlike => qr/-icdisc(?:\s|\x20)<file>/, 'CLI help does not advertise the removed -icdisc flag' ],
    [ like => qr/-idataset-json <files\.\.\.>/, 'CLI help documents Dataset-JSON input' ],
    [ like => qr/-idataset-xml <files\.\.\.>/, 'CLI help documents Dataset-XML input' ],
    [ like => qr/--define-xml <file>/, 'CLI help documents the required Define-XML metadata' ],
    [ like => qr/-ifhir <files\.\.\.>/, 'CLI help documents FHIR Bundle input' ],
    [ like => qr/FHIR R4 JSON Bundles, including mCODE/, 'CLI help documents mCODE as a FHIR profile' ],
    [ like => qr/\[ALIVE\|DECEASED\|UNKNOWN_STATUS\]/, 'CLI help documents supported vitalStatus fallback values' ],
    [ like => qr/Supported:\s+individuals,\s+biosamples,\s+datasets,\s+cohorts/s, 'CLI help documents the supported BFF entities' ],
    [ like => qr/biosamples are emitted from -ipxf, cBioPortal samples,\s+FHIR Specimen, OMOP SPECIMEN, or mapping rules/s, 'CLI help documents all first-class biosample sources' ],
    [ like => qr/Mapping V2 YAML or JSON file targeting\s+Beacon schema 2\.0\.0/s, 'CLI help documents the mapping and Beacon schema contract' ],
    [ like => qr/datasets and\s+cohorts are synthesized from individuals/s, 'CLI help documents synthesized dataset and cohort entities' ],
    [ like => qr/Use with -obff and --out-dir/s, 'CLI help documents that entity mode keeps -obff explicit' ],
    [ like => qr/-obff FILE keeps the individuals-only BFF behavior\./s, 'CLI help documents the individuals-only BFF behavior' ],
    [ like => qr/-obff --entities \.\.\. --out-dir DIR writes one file per requested BFF entity\./s, 'CLI help documents the explicit entity-aware BFF form' ],
    [ like => qr/-oomop --out-dir DIR writes one file per emitted OMOP table\./s, 'CLI help documents the out-dir based OMOP table output mode' ],
    [ like => qr/-oomop\s+OMOP-CDM CSV table output \(use with --out-dir\)/s, 'CLI help documents OMOP output as out-dir based multi-file output' ],
    [ like => qr/--out-name k=file\s+Override one multi-file output name/s, 'CLI help documents the shared multi-file rename flag' ],
);

for my $check (@help_contract) {
    my ( $kind, $pattern, $description ) = @{$check};
    if ( $kind eq 'like' ) {
        like( $help, $pattern, $description );
    }
    else {
        unlike( $help, $pattern, $description );
    }
}

my $usage_error_output =
  qx{$^X $cli -ipxf t/pxf2bff/in/pxf.json --entities biosamples --out-dir $tmpdir 2>&1};
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
