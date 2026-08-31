#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use File::Spec;
use Test::More;
use Test::ConvertPheno qw(cli_script_path test_ohdsi_db_dir test_tmpdir);
use Convert::Pheno::CLI::Args qw(build_cli_request);

my $tmpdir = test_tmpdir();

sub parse_cli_request {
    my (@argv) = @_;
    return build_cli_request(
        argv        => \@argv,
        usage_error => sub { die @_ },
        schema_file => 'share/schema/mapping-v2.json',
        out_dir     => $tmpdir,
        color       => 1,
    );
}

sub parse_cli_error {
    my (@argv) = @_;
    my $error;
    eval { parse_cli_request(@argv); 1 } or $error = $@;
    return $error;
}

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
        '-iomop', 't/omop2bff/in/mimic_specimen',
        '-obff',  'individuals.json',
    ],
    usage_error => sub { die @_ },
    schema_file => 'share/schema/mapping-v2.json',
    out_dir     => $tmpdir,
    color       => 1,
);
is_deeply(
    $request->{data}{in_files},
    ['t/omop2bff/in/mimic_specimen'],
    'CLI parser accepts an OMOP table directory',
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

for my $case (
    [ i2b2 => 't/i2b22bff/in', '-ii2b2', 'i2b22bff' ],
    [ pcornet => 't/pcornet2bff/in', '-ipcornet', 'pcornet2bff' ],
    [ sentinel => 't/sentinel2bff/in', '-isentinel', 'sentinel2bff' ],
) {
    my ( $source, $directory, $flag, $method ) = @{$case};
    $request = build_cli_request(
        argv => [ $flag, $directory, '-obff', 'individuals.json' ],
        usage_error => sub { die @_ },
        schema_file => 'share/schema/mapping-v2.json',
        out_dir     => $tmpdir,
        color       => 1,
    );
    is( $request->{data}{method}, $method, "CLI parser accepts compact $source input" );
    is_deeply( $request->{data}{in_files}, [$directory], "CLI parser retains the $source table package" );
}

$request = build_cli_request(
    argv => [
        '-i', 'PCORnet-CDM', 't/pcornet2bff/in',
        '-o', 'pxf', 'phenopackets.json',
    ],
    usage_error => sub { die @_ },
    schema_file => 'share/schema/mapping-v2.json',
    out_dir     => $tmpdir,
    color       => 1,
);
is( $request->{data}{method}, 'pcornet2pxf', 'CLI parser normalizes the generic PCORnet CDM name' );

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

is( parse_cli_request('--help')->{action},    'help',    'CLI parser returns the help action' );
is( parse_cli_request('--man')->{action},     'man',     'CLI parser returns the manual action' );
is( parse_cli_request('--version')->{action}, 'version', 'CLI parser returns the version action' );

$request = parse_cli_request(
    '-iredcap',            't/redcap2bff/in/redcap_data.csv',
    '--redcap-dictionary', 't/redcap2bff/in/redcap_dictionary.csv',
    '--mapping-file',      't/redcap2bff/in/redcap_mapping.yaml',
    '-opxf',               'redcap.json',
    '--separator',         ',',
    '--self-validate-schema',
    '--debug',             2,
    '--verbose',
    '--no-color',
    '--log=parser.json',
    '--term-audit',       'term-audit.xlsx',
    '--path-to-ohdsi-db', test_ohdsi_db_dir(),
    '--exposures-file',   'share/db/concepts_candidates_2_exposure.csv',
    '--test',
    '-O',
);

is( $request->{data}{method}, 'redcap2pxf', 'CLI parser builds the REDCap to PXF route' );
is( $request->{data}{redcap_dictionary}, 't/redcap2bff/in/redcap_dictionary.csv', 'CLI parser retains the REDCap dictionary' );
is( $request->{data}{sep}, ',', 'CLI parser retains the requested separator' );
is( $request->{data}{debug}, 2, 'CLI parser retains the debug level' );
is( $request->{data}{verbose}, 1, 'CLI parser enables verbose mode' );
is( $request->{data}{self_validate_schema}, 1, 'CLI parser enables mapping-schema self-validation' );
is( $request->{color}, 0, 'CLI parser accepts --no-color' );
is( $request->{overwrite}, 1, 'CLI parser accepts overwrite mode' );
is( $request->{log_file}, File::Spec->catfile( $tmpdir, 'parser.json' ), 'CLI parser resolves the log path' );
is( $request->{data}{term_audit_file}, File::Spec->catfile( $tmpdir, 'term-audit.xlsx' ), 'CLI parser resolves the terminology audit path' );

$request = parse_cli_request(
    '-icdisc-odm',   't/cdiscodm2bff/in/cdisc_odm_data.xml',
    '--mapping-file', 't/redcap2bff/in/redcap_mapping.yaml',
    '-obff',          'cdisc.json',
);
is( $request->{data}{method}, 'cdiscodm2bff', 'CLI parser builds the CDISC-ODM route' );

$request = parse_cli_request(
    '-i', 'phenopackets',
    't/pxf2bff/in/pxf.json',
    '-o', 'beacon',
    'individuals.json',
);
is( $request->{data}{method}, 'pxf2bff', 'generic CLI syntax accepts model-name aliases' );

$request = parse_cli_request(
    '-i', 'omop-cdm',
    't/omop2bff/in/omop_cdm_eunomia.sql',
    '-o', 'bff',
    'individuals.json',
);
is( $request->{data}{method}, 'omop2bff', 'generic CLI syntax accepts OMOP input' );

$request = parse_cli_request(
    '-i', 'ehrbase',
    't/openehr2bff/in/gecco_personendaten_patient.json',
    '-o', 'bff',
    'individuals.json',
);
is( $request->{data}{method}, 'openehr2bff', 'generic CLI syntax accepts the EHRbase alias' );

$request = parse_cli_request(
    '-ipxf',      't/pxf2bff/in/pxf.json',
    '-obff',
    '--entities', qw(individuals biosamples),
    '--out-dir',  $tmpdir,
    '--out-name', 'biosamples=samples.json',
);
is(
    $request->{data}{output_name_overrides}{biosamples},
    File::Spec->catfile( $tmpdir, 'samples.json' ),
    'CLI parser resolves entity output-name overrides',
);

my @generic_route_cases = (
    [ 'defaults OMOP-CDM input to BFF output', 'omop2bff',
        [ '-i', 'omop', 't/omop2bff/in/omop_cdm_eunomia.sql' ] ],
    [ 'defaults FHIR input to BFF output', 'fhir2bff',
        [ '-i', 'fhir', 't/fhir2bff/in/patient-bundle.json' ] ],
    [ 'defaults openEHR input to BFF output', 'openehr2bff',
        [ '-i', 'openehr', 't/openehr2bff/in/gecco_personendaten_patient.json' ] ],
    [ 'defaults Dataset-JSON input to BFF output', 'datasetjson2bff',
        [ '-i', 'dataset-json', @datasetjson_files ] ],
    [ 'defaults Dataset-XML input to BFF output', 'datasetxml2bff',
        [ '-i', 'dataset-xml', @datasetxml_files,
            '--define-xml', 't/datasetxml2bff/in/define.xml' ] ],
    [ 'accepts FHIR to OMOP output', 'fhir2omop',
        [ '-i', 'fhir', 't/fhir2bff/in/patient-bundle.json',
            '-o', 'omop', '--ohdsi-db' ] ],
    [ 'accepts Dataset-JSON to OMOP output', 'datasetjson2omop',
        [ '-i', 'dataset-json', @datasetjson_files,
            '-o', 'omop', '--ohdsi-db' ] ],
    [ 'accepts Dataset-XML to OMOP output', 'datasetxml2omop',
        [ '-i', 'dataset-xml', @datasetxml_files,
            '--define-xml', 't/datasetxml2bff/in/define.xml',
            '-o', 'omop', '--ohdsi-db' ] ],
    [ 'accepts REDCap tabular input', 'redcap2bff',
        [ '-i', 'redcap', 't/redcap2bff/in/redcap_data.csv',
            '-o', 'bff', 'individuals.json',
            '--redcap-dictionary', 't/redcap2bff/in/redcap_dictionary.csv',
            '--mapping-file', 't/redcap2bff/in/redcap_mapping.yaml' ] ],
    [ 'accepts CDISC-ODM tabular input', 'cdiscodm2bff',
        [ '-i', 'cdisc-odm', 't/cdiscodm2bff/in/cdisc_odm_data.xml',
            '-o', 'bff', 'individuals.json',
            '--mapping-file', 't/redcap2bff/in/redcap_mapping.yaml' ] ],
    [ 'accepts CSV tabular input', 'csv2bff',
        [ '-i', 'csv', 't/csv2bff/in/csv_data.csv',
            '-o', 'bff', 'individuals.json',
            '--mapping-file', 't/csv2bff/in/csv_mapping.yaml' ] ],
);

for my $case (@generic_route_cases) {
    my ( $description, $method, $argv ) = @{$case};
    is( parse_cli_request( @{$argv} )->{data}{method}, $method,
        "generic CLI syntax $description" );
}

for my $output_type (qw(csv jsonf jsonld)) {
    my $parsed = parse_cli_request(
        '-i', 'pxf', 't/pxf2bff/in/pxf.json',
        '-o', $output_type, "output.$output_type",
    );
    is(
        $parsed->{data}{method},
        "pxf2$output_type",
        "generic CLI syntax accepts $output_type output",
    );
}

my @cli_error_cases = (
    [ 'rejects --default-vital-status without PXF output',
        qr/--default-vital-status> is only valid with PXF output/,
        '-ipxf', 't/pxf2bff/in/pxf.json', '-obff', 'individuals.json',
        '--default-vital-status', 'DECEASED' ],
    [ 'reports the removed -oomop PREFIX form', qr/no longer accepts a prefix/,
        '-ibff', 't/bff2pxf/in/individuals.json', '-oomop', 'old-prefix',
        '--out-dir', $tmpdir, '--ohdsi-db' ],
    [ 'rejects unsupported same-format routes', qr/Unsupported conversion <bff2bff>/,
        '-ibff', 't/bff2pxf/in/individuals.json', '-obff', 'individuals.json' ],
    [ 'reports the cBioPortal package requirement',
        qr/valid cBioPortal study directory or ZIP file/,
        '-icbioportal', 'missing-study.zip', '-opxf', 'phenopackets.json' ],
    [ 'requires Define-XML with Dataset-XML input',
        qr/accompanying Define-XML file with --define-xml/,
        '-idataset-xml', @datasetxml_files, '-obff', 'individuals.json' ],
    [ 'rejects an unsupported generic input type', qr/Unsupported input type <unknown>/,
        '-i', 'unknown', 'input.json', '-o', 'bff', 'output.json' ],
    [ 'rejects an unsupported generic output type', qr/Unsupported output type <unknown>/,
        '-i', 'pxf', 't/pxf2bff/in/pxf.json', '-o', 'unknown', 'output.json' ],
    [ 'rejects mixed generic and compact input syntax',
        qr/either the generic <-i\/-o> syntax or the compact/,
        '-i', 'pxf', '-ipxf', 't/pxf2bff/in/pxf.json',
        '-o', 'bff', 't/pxf2bff/in/pxf.json', 'output.json' ],
    [ 'rejects generic output without generic input', qr/<-o> requires <-i>/,
        '-o', 'pxf', 'output.json' ],
    [ 'rejects comma-separated entities', qr/space-separated list/,
        '-ipxf', 't/pxf2bff/in/pxf.json', '-obff',
        '--entities', 'individuals,biosamples' ],
    [ 'rejects unknown BFF entities', qr/Unsupported entity <unknown>/,
        '-ipxf', 't/pxf2bff/in/pxf.json', '-obff', '--entities', 'unknown' ],
    [ 'rejects entity selection for non-BFF output',
        qr/<--entities> is only valid with BFF output/,
        '-ipxf', 't/pxf2bff/in/pxf.json', '-opxf', 'output.json',
        '--entities', 'individuals' ],
    [ 'rejects streaming for non-OMOP input',
        qr/<--stream> is only valid with <-iomop> and <-obff>/,
        '-ipxf', 't/pxf2bff/in/pxf.json', '-obff', 'output.json', '--stream' ],
    [ 'rejects unsupported openEHR to OMOP output',
        qr/openEHR input path currently supports only BFF or PXF output/,
        '-i', 'openehr', 't/openehr2bff/in/gecco_personendaten_patient.json',
        '-o', 'omop', '--ohdsi-db' ],
    [ 'rejects invalid default vital status values', qr/Unsupported value <MISSING>/,
        '-ibff', 't/bff2pxf/in/individuals.json', '-opxf', 'output.json',
        '--default-vital-status', 'MISSING' ],
    [ 'rejects malformed output-name overrides', qr/Invalid <--out-name> value/,
        '-ipxf', 't/pxf2bff/in/pxf.json', '-obff', '--entities', 'individuals',
        '--out-name', 'individuals.json' ],
    [ 'requires an output-name entity to be requested',
        qr/entity <biosamples> must also be requested/,
        '-ipxf', 't/pxf2bff/in/pxf.json', '-obff', '--entities', 'individuals',
        '--out-name', 'biosamples=samples.json' ],
    [ 'rejects unsupported terminology audit extensions',
        qr/\.tsv, \.tsv\.gz, or \.xlsx/,
        '-icsv', 't/csv2bff/in/csv_data.csv',
        '--mapping-file', 't/csv2bff/in/csv_mapping.yaml',
        '-obff', 'output.json', '--term-audit', 'audit.csv' ],
    [ 'rejects Define-XML outside Dataset input', qr/<--define-xml> is only valid/,
        '-ipxf', 't/pxf2bff/in/pxf.json', '-obff', 'output.json',
        '--define-xml', 't/datasetxml2bff/in/define.xml' ],
    [ 'requires an OHDSI database for OMOP output', qr/Please use --ohdsi-db/,
        '-ibff', 't/bff2pxf/in/individuals.json', '-oomop' ],
    [ 'requires the REDCap dictionary', qr/valid REDCap data dictionary/,
        '-iredcap', 't/redcap2bff/in/redcap_data.csv',
        '--mapping-file', 't/redcap2bff/in/redcap_mapping.yaml',
        '-obff', 'output.json' ],
    [ 'requires a mapping file for CSV input', qr/valid mapping file/,
        '-icsv', 't/csv2bff/in/csv_data.csv', '-obff', 'output.json' ],
    [ 'rejects OMOP table selection for other inputs',
        qr/<--omop-tables> is only valid with <-iomop>/,
        '-ipxf', 't/pxf2bff/in/pxf.json', '-obff', 'output.json',
        '--omop-tables', 'PERSON' ],
);

for my $case (@cli_error_cases) {
    my ( $description, $match, @argv ) = @{$case};
    like( parse_cli_error(@argv), $match, "CLI parser $description" );
}

my $cli = cli_script_path();
plan skip_all => "convert-pheno CLI not found at $cli" unless -f $cli;

my $help = qx{$^X $cli --help 2>&1};
is( $? >> 8, 0, 'CLI help exits successfully' );
my @help_contract = (
    [ like => qr/--search <type>/, 'CLI help documents --search' ],
    [ like => qr/--min-text-similarity-score <s>/, 'CLI help documents --min-text-similarity-score' ],
    [ like => qr/--text-similarity-method <m>/, 'CLI help documents --text-similarity-method' ],
    [ like => qr/--levenshtein-weight <w>/, 'CLI help documents --levenshtein-weight' ],
    [ like => qr/--term-audit <file>/, 'CLI help documents --term-audit' ],
    [ like => qr/\.tsv\|\.tsv\.gz\|\.xlsx/, 'CLI help documents terminology audit formats' ],
    [ unlike => qr/--term-audit-tsv/, 'CLI help omits the superseded --term-audit-tsv option' ],
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
    [ like => qr/-ii2b2 <paths\.\.\.>/, 'CLI help documents i2b2 table input' ],
    [ like => qr/-ipcornet <paths\.\.\.>/, 'CLI help documents PCORnet CDM table input' ],
    [ like => qr/-isentinel <paths\.\.\.>/, 'CLI help documents Sentinel CDM table input' ],
    [ like => qr/OMOP-CDM CSV\/TSV files, one directory or ZIP package/s, 'CLI help documents OMOP table packages' ],
    [ like => qr/exported tables rather than live databases/, 'CLI help states the clinical CDM input boundary' ],
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
