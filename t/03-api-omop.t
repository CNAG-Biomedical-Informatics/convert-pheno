#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use Test::Warn;
use Test::ConvertPheno
  qw(build_convert temp_output_file test_ohdsi_db_dir structured_files_match load_csv_table
  csv_headers_from_file write_csv_rows load_json_file write_json_file write_zip_from_files);
use File::Copy qw(copy);
use File::Temp qw(tempdir tempfile);
use File::Spec;
use JSON::XS;
use Convert::Pheno::Source qw(source_adapter);

my $test_ohdsi_db_dir = test_ohdsi_db_dir();

sub omop_table_members {
    my ($prefix) = @_;
    return [ map {
        +{
            file => "t/omop2bff/in/$_.csv",
            name => defined $prefix ? "$prefix/$_.csv" : "$_.csv",
        }
    } qw(CONCEPT DRUG_EXPOSURE PERSON) ];
}

my @snapshot_cases = (
    {
        name     => 'omop2bff',
        method   => 'omop2bff',
        in_files => ['t/omop2bff/in/omop_cdm_eunomia.sql'],
        sep      => ',',
        out_file => 't/omop2bff/out/individuals.json',
    },
    {
        name     => 'omop2pxf',
        method   => 'omop2pxf',
        in_files => ['t/omop2bff/in/omop_cdm_eunomia.sql'],
        sep      => ',',
        out_file => 't/omop2pxf/out/pxf.json',
    },
);

for my $case (@snapshot_cases) {
    my $tmp_file = temp_output_file();
    my $convert  = build_convert(
        in_files  => $case->{in_files},
        sep       => $case->{sep},
        out_file  => $tmp_file,
        method    => $case->{method},
    );

    $convert->${ \$case->{method} };

    ok( structured_files_match( $case->{out_file}, $tmp_file ), $case->{name} );
}

{
    my $mapping = {
        mappingVersion => 2,
        source         => { profile => 'omop' },
        target         => {
            model         => 'beacon',
            schemaVersion => '2.0.0',
        },
        project => {
            id          => 'eunomia-study',
            version     => '1',
            description => 'Synthetic OMOP study',
        },
        beacon => {
            datasets => {
                defaults => {
                    name        => 'Eunomia dataset',
                    externalUrl => 'https://example.org/eunomia',
                },
            },
            cohorts => {
                defaults => {
                    name       => 'Eunomia cohort',
                    cohortType => 'study-defined',
                },
            },
        },
    };
    my ( $mapping_fh, $mapping_file ) = tempfile( SUFFIX => '.json', UNLINK => 1 );
    close $mapping_fh;
    write_json_file( $mapping_file, $mapping );

    my $convert = build_convert(
        in_files => [
            't/omop2bff/in/CONCEPT.csv',
            't/omop2bff/in/DRUG_EXPOSURE.csv',
            't/omop2bff/in/PERSON.csv',
        ],
        mapping_file     => $mapping_file,
        schema_file      => 'share/schema/mapping-v2.json',
        entities         => [qw(individuals datasets cohorts)],
        ohdsi_db         => 1,
        path_to_ohdsi_db => $test_ohdsi_db_dir,
        method           => 'omop2bff',
    );
    my $bundle  = $convert->_run_bundle_view;
    my $dataset = $bundle->entities('datasets')->[0];
    my $cohort  = $bundle->entities('cohorts')->[0];

    is( $dataset->{id}, 'eunomia-study', 'OMOP metadata mapping uses project.id as the dataset id' );
    is( $dataset->{name}, 'Eunomia dataset', 'OMOP metadata mapping overrides the dataset name' );
    is( $dataset->{externalUrl}, 'https://example.org/eunomia', 'OMOP metadata mapping adds dataset properties' );
    is( $cohort->{id}, 'eunomia-study-cohort', 'OMOP metadata mapping derives the cohort id from project.id' );
    is( $cohort->{name}, 'Eunomia cohort', 'OMOP metadata mapping overrides the cohort name' );
    ok(
        !exists $bundle->entities('individuals')->[0]{info}{project},
        'project metadata is not propagated into OMOP individuals',
    );
}

{
    my $directory = tempdir( CLEANUP => 1 );
    for my $table (qw(CONCEPT DRUG_EXPOSURE PERSON)) {
        copy(
            "t/omop2bff/in/$table.csv",
            File::Spec->catfile( $directory, "$table.csv" ),
        ) or die "Cannot prepare OMOP directory fixture: $!";
    }

    my $output = temp_output_file();
    my $convert = build_convert(
        in_files        => [$directory],
        out_file        => $output,
        ohdsi_db        => 1,
        path_to_ohdsi_db => $test_ohdsi_db_dir,
        method          => 'omop2bff',
    );
    $convert->omop2bff;
    ok(
        structured_files_match( 't/omop2bff/out/ohdsi.json', $output ),
        'OMOP directory input preserves existing CSV conversion output',
    );
}

{
    my $directory = tempdir( CLEANUP => 1 );
    my $archive = File::Spec->catfile( $directory, 'omop-export.zip' );
    write_zip_from_files( $archive, omop_table_members('tables') );

    my $output = temp_output_file();
    my $convert = build_convert(
        in_files        => [$archive],
        out_file        => $output,
        ohdsi_db        => 1,
        path_to_ohdsi_db => $test_ohdsi_db_dir,
        method          => 'omop2bff',
    );
    $convert->omop2bff;
    ok(
        structured_files_match( 't/omop2bff/out/ohdsi.json', $output ),
        'OMOP ZIP input preserves existing CSV conversion output',
    );
}

{
    my $directory = tempdir( CLEANUP => 1 );
    my $archive = File::Spec->catfile( $directory, 'duplicate.zip' );
    write_zip_from_files(
        $archive,
        [
            { file => 't/omop2bff/in/PERSON.csv', name => 'a/PERSON.csv' },
            { file => 't/omop2bff/in/PERSON.csv', name => 'b/PERSON.csv' },
        ],
    );
    my $convert = build_convert(
        in_files => [$archive],
        method   => 'omop2bff',
    );
    my $error;
    eval { $convert->omop2bff; 1 } or $error = $@;
    like(
        $error,
        qr/duplicate table filename <PERSON\.csv>/,
        'OMOP ZIP input rejects duplicate table files',
    );
}

{
    my $directory = tempdir( CLEANUP => 1 );
    my $archive = File::Spec->catfile( $directory, 'unsafe.zip' );
    write_zip_from_files(
        $archive,
        [ { file => 't/omop2bff/in/PERSON.csv', name => '../PERSON.csv' } ],
    );
    my $convert = build_convert(
        in_files => [$archive],
        method   => 'omop2bff',
    );
    my $error;
    eval { $convert->omop2bff; 1 } or $error = $@;
    like(
        $error,
        qr/unsafe entry <\.\.\/PERSON\.csv>/,
        'OMOP ZIP input rejects path traversal entries',
    );
}

{
    my $directory = tempdir( CLEANUP => 1 );
    my $archive = File::Spec->catfile( $directory, 'limited.zip' );
    write_zip_from_files( $archive, omop_table_members() );

    my $convert = build_convert(
        in_files => [$archive],
        max_archive_uncompressed_bytes => 1,
        method   => 'omop2bff',
    );
    my $error;
    eval { $convert->omop2bff; 1 } or $error = $@;
    like(
        $error,
        qr/exceeds the allowed uncompressed size/,
        'OMOP ZIP input enforces its configured extraction limit',
    );

    $convert = build_convert(
        in_files => [ $archive, 't/omop2bff/in/PERSON.csv' ],
        method   => 'omop2bff',
    );
    $error = undef;
    eval { $convert->omop2bff; 1 } or $error = $@;
    like(
        $error,
        qr/must be supplied as the only input path/,
        'OMOP ZIP packages cannot be mixed with separate table inputs',
    );
}

{
    my $loader = build_convert(
        in_files => ['t/omop2bff/in/omop_cdm_eunomia.sql'],
        sep      => ',',
        method   => 'omop2bff',
    );
    my $tables = source_adapter( $loader, 'omop' )->load->data;
    my $before = JSON::XS->new->canonical->encode($tables);

    for my $case (@snapshot_cases) {
        my $convert = build_convert(
            data   => $tables,
            method => $case->{method},
        );
        my $result = $convert->${ \$case->{method} };

        is_deeply(
            $result,
            load_json_file( $case->{out_file} ),
            "$case->{name} table-oriented memory input matches the existing fixture",
        );
        is(
            JSON::XS->new->canonical->encode($tables),
            $before,
            "$case->{name} leaves caller-owned OMOP tables unchanged",
        );
    }
}

{
    my $convert = build_convert(
        in_files => [
            't/omop2bff/in/CONCEPT.csv',
            't/omop2bff/in/DRUG_EXPOSURE.csv',
            't/omop2bff/in/PERSON.csv',
            't/omop2bff/in/DUMMY.csv',
        ],
        out_file => temp_output_file(),
        ohdsi_db => 1,
        path_to_ohdsi_db => $test_ohdsi_db_dir,
        method   => 'omop2bff',
    );

    warning_is { $convert->omop2bff }
      qq(<DUMMY> is not a valid table in OMOP-CDM\n),
      'warns on unsupported OMOP table';
}

{
    my $convert = build_convert(
        in_files => [
            't/omop2bff/in/CONCEPT.csv',
            't/omop2bff/in/DRUG_EXPOSURE.csv',
            't/omop2bff/in/PERSON.csv',
        ],
        out_file => temp_output_file(),
        ohdsi_db => 1,
        path_to_ohdsi_db => $test_ohdsi_db_dir,
        method   => 'omop2bff',
    );

    my $tmp_file = $convert->{out_file};
    $convert->omop2bff;
    ok( structured_files_match( 't/omop2bff/out/ohdsi.json', $tmp_file ),
        'omop2bff with OHDSI db matches reduced fixture' );
}

{
    my $tmp_dir = tempdir( CLEANUP => 1 );
    my $concept_file = File::Spec->catfile( $tmp_dir, 'CONCEPT.csv' );
    my $headers      = csv_headers_from_file('t/omop2bff/in/CONCEPT.csv');
    my $rows         = load_csv_table('t/omop2bff/in/CONCEPT.csv');
    my @filtered_rows =
      grep { $_->{concept_id} ne '8507' && $_->{concept_id} ne '8532' } @{$rows};
    write_csv_rows( $concept_file, $headers, \@filtered_rows );

    my @in_files = (
        $concept_file,
        't/omop2bff/in/DRUG_EXPOSURE.csv',
        't/omop2bff/in/PERSON.csv',
    );

    {
        my $convert = build_convert(
            in_files => \@in_files,
            out_file => temp_output_file(),
            method   => 'omop2bff',
        );

        my $error;
        eval { $convert->omop2bff; 1 } or $error = $@;
        like(
            $error,
            qr/Could not find concept_id:<(?:8507|8532)> in provided CONCEPT table\./,
            'omop2bff without --ohdsi-db fails when gender concepts are missing locally'
        );
    }

    my $tmp_file = temp_output_file();
    my $convert  = build_convert(
        in_files  => \@in_files,
        out_file  => $tmp_file,
        ohdsi_db  => 1,
        path_to_ohdsi_db => $test_ohdsi_db_dir,
        method    => 'omop2bff',
    );

    $convert->omop2bff;
    my $data = load_json_file($tmp_file);
    my %sex_counts;
    $sex_counts{ ( $_->{sex} || {} )->{label} }++ for @{$data};

    is( $sex_counts{'Not Available'} || 0, 0,
        'omop2bff with --ohdsi-db resolves missing gender concepts instead of degrading to Not Available' );
}

{
    my $out_dir = tempdir( CLEANUP => 1 );
    my $convert = build_convert(
        in_files => ['t/omop2bff/in/omop_cdm_eunomia.sql'],
        out_dir  => $out_dir,
        out_file => temp_output_file(),
        sql2csv  => 1,
        method   => 'omop2bff',
    );

    $convert->omop2bff;

    my $specimen_csv = File::Spec->catfile( $out_dir, 'SPECIMEN.csv' );
    ok( -f $specimen_csv, 'sql2csv exports SPECIMEN.csv by default for supported OMOP tables' );
    is_deeply( load_csv_table($specimen_csv), [], 'empty specimen fixture exports as an empty CSV table' );
}

done_testing();
