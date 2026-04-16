#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use File::Spec;
use File::Temp qw(tempfile);
use JSON::XS qw(decode_json);

use Convert::Pheno::OMOP::ToBFF::Biosamples
  qw(extract_participant_biosamples);
use Test::ConvertPheno qw(
  build_convert
  cli_script_path
  ensure_clean_dir
  load_json_file
  remove_dir_if_exists
  slurp_file
  test_tmpdir
  write_csv_rows
);

my $cli = cli_script_path();
my $tmpdir = test_tmpdir();

sub concept_headers {
    return [
        qw(
          concept_id
          concept_name
          domain_id
          vocabulary_id
          concept_class_id
          standard_concept
          concept_code
          valid_start_date
          valid_end_date
          invalid_reason
          )
    ];
}

sub person_headers {
    return [
        qw(
          person_id
          gender_concept_id
          year_of_birth
          month_of_birth
          day_of_birth
          birth_datetime
          race_concept_id
          ethnicity_concept_id
          location_id
          provider_id
          care_site_id
          person_source_value
          gender_source_value
          gender_source_concept_id
          race_source_value
          race_source_concept_id
          ethnicity_source_value
          ethnicity_source_concept_id
          )
    ];
}

sub specimen_headers {
    return [
        qw(
          specimen_id
          person_id
          specimen_concept_id
          specimen_type_concept_id
          specimen_date
          specimen_datetime
          quantity
          unit_concept_id
          anatomic_site_concept_id
          disease_status_concept_id
          specimen_source_id
          specimen_source_value
          unit_source_value
          anatomic_site_source_value
          disease_status_source_value
          )
    ];
}

sub write_minimal_omop_inputs {
    my ( $dir, %arg ) = @_;

    my $concept = File::Spec->catfile( $dir, 'CONCEPT.csv' );
    my $person  = File::Spec->catfile( $dir, 'PERSON.csv' );
    my $specimen = File::Spec->catfile( $dir, 'SPECIMEN.csv' );

    write_csv_rows(
        $concept,
        concept_headers(),
        [
            {
                concept_id         => 8507,
                concept_name       => 'Male',
                domain_id          => 'Gender',
                vocabulary_id      => 'SNOMED',
                concept_class_id   => 'Clinical Finding',
                standard_concept   => 'S',
                concept_code       => '248153007',
                valid_start_date   => '1970-01-01',
                valid_end_date     => '2099-12-31',
                invalid_reason     => '',
            },
            {
                concept_id         => 9001,
                concept_name       => 'Blood specimen',
                domain_id          => 'Specimen',
                vocabulary_id      => 'SNOMED',
                concept_class_id   => 'Specimen',
                standard_concept   => 'S',
                concept_code       => '119297000',
                valid_start_date   => '1970-01-01',
                valid_end_date     => '2099-12-31',
                invalid_reason     => '',
            },
            {
                concept_id         => 9003,
                concept_name       => 'Liver structure',
                domain_id          => 'Specimen',
                vocabulary_id      => 'SNOMED',
                concept_class_id   => 'Body Structure',
                standard_concept   => 'S',
                concept_code       => '10200004',
                valid_start_date   => '1970-01-01',
                valid_end_date     => '2099-12-31',
                invalid_reason     => '',
            },
            {
                concept_id         => 9004,
                concept_name       => 'Positive finding',
                domain_id          => 'Observation',
                vocabulary_id      => 'SNOMED',
                concept_class_id   => 'Clinical Finding',
                standard_concept   => 'S',
                concept_code       => '10828004',
                valid_start_date   => '1970-01-01',
                valid_end_date     => '2099-12-31',
                invalid_reason     => '',
            },
        ]
    );

    write_csv_rows(
        $person,
        person_headers(),
        [
            {
                person_id                  => 1,
                gender_concept_id          => 8507,
                year_of_birth              => 1980,
                month_of_birth             => 1,
                day_of_birth               => 15,
                birth_datetime             => '1980-01-15 00:00:00',
                race_concept_id            => 0,
                ethnicity_concept_id       => 0,
                location_id                => '\\N',
                provider_id                => '\\N',
                care_site_id               => '\\N',
                person_source_value        => 'subject-1',
                gender_source_value        => 'Male',
                gender_source_concept_id   => 0,
                race_source_value          => '',
                race_source_concept_id     => 0,
                ethnicity_source_value     => '',
                ethnicity_source_concept_id => 0,
            },
        ]
    );

    if ( !exists $arg{with_specimen} || $arg{with_specimen} ) {
        write_csv_rows(
            $specimen,
            specimen_headers(),
            [
                {
                    specimen_id                 => 101,
                    person_id                   => 1,
                    specimen_concept_id         => 9001,
                    specimen_type_concept_id    => 0,
                    specimen_date               => '2020-05-10',
                    specimen_datetime           => '2020-05-10 09:30:00',
                    quantity                    => 2,
                    unit_concept_id             => 0,
                    anatomic_site_concept_id    => 9003,
                    disease_status_concept_id   => 9004,
                    specimen_source_id          => 'SRC-101',
                    specimen_source_value       => 'Specimen note 101',
                    unit_source_value           => '',
                    anatomic_site_source_value  => 'Liver',
                    disease_status_source_value => 'Positive',
                },
                {
                    specimen_id                 => 102,
                    person_id                   => 1,
                    specimen_concept_id         => 0,
                    specimen_type_concept_id    => 0,
                    specimen_date               => '2021-06-11',
                    specimen_datetime           => '2021-06-11 10:30:00',
                    quantity                    => 1,
                    unit_concept_id             => 0,
                    anatomic_site_concept_id    => 0,
                    disease_status_concept_id   => 0,
                    specimen_source_id          => 'SRC-102',
                    specimen_source_value       => '',
                    unit_source_value           => '',
                    anatomic_site_source_value  => '',
                    disease_status_source_value => '',
                },
            ]
        );
    }

    return (
        concept  => $concept,
        person   => $person,
        specimen => $specimen,
    );
}

sub load_json_lines {
    my ($file) = @_;
    my $content = slurp_file($file);
    my @items = grep { length } split /\n/, $content;
    return [ map { decode_json($_) } @items ];
}

sub mimic_specimen_fixture_dir {
    return File::Spec->catdir( 't', 'omop2bff', 'in', 'mimic_specimen' );
}

sub mimic_specimen_fixture_files {
    my $dir = mimic_specimen_fixture_dir();
    return (
        concept  => File::Spec->catfile( $dir, 'CONCEPT.csv' ),
        person   => File::Spec->catfile( $dir, 'PERSON.csv' ),
        specimen => File::Spec->catfile( $dir, 'SPECIMEN.csv' ),
    );
}

sub find_biosample_by_id {
    my ( $biosamples, $id ) = @_;
    for my $biosample ( @{$biosamples} ) {
        return $biosample if $biosample->{id} eq $id;
    }
    return;
}

{
    no warnings 'redefine';

    local *Convert::Pheno::OMOP::ToBFF::Biosamples::map2ohdsi = sub {
        my ($arg) = @_;
        return {
            id    => "OHDSI:$arg->{concept_id}",
            label => "label-$arg->{concept_id}",
        };
    };

    my $self = bless( { data_ohdsi_dict => {} }, 'Convert::Pheno' );
    my $participant = {
        PERSON => {
            person_id      => 5,
            birth_datetime => '1980-01-15 00:00:00',
        },
        SPECIMEN => [
            {
                specimen_id               => 901,
                person_id                 => 5,
                specimen_concept_id       => 1001,
                specimen_type_concept_id  => 1004,
                specimen_date             => '2020-03-01',
                anatomic_site_concept_id  => 1002,
                disease_status_concept_id => 1003,
                specimen_source_value     => 'first note',
            },
            {
                specimen_id               => 902,
                person_id                 => 5,
                specimen_concept_id       => 0,
                specimen_type_concept_id  => 0,
                specimen_date             => '2021-04-01',
                anatomic_site_concept_id  => 0,
                disease_status_concept_id => 0,
                specimen_source_value     => 70003,
            },
        ],
    };

    my $got = extract_participant_biosamples( $self, $participant, { id => '5' } );

    is( scalar @{$got}, 2, 'maps one biosample per specimen row' );
    is( $got->[0]{id}, '901', 'uses specimen_id as biosample id' );
    is( $got->[0]{individualId}, '5', 'uses the participant individual id' );
    is( $got->[0]{collectionDate}, '2020-03-01', 'maps specimen_date to collectionDate' );
    is( $got->[0]{collectionMoment}, 'P40Y', 'derives collectionMoment from specimen_date and birth date' );
    is( $got->[0]{sampleOriginType}{id}, 'OHDSI:1001', 'maps specimen_concept_id to sampleOriginType' );
    is( $got->[0]{sampleOriginDetail}{id}, 'OHDSI:1002', 'maps anatomic_site_concept_id to sampleOriginDetail' );
    is( $got->[0]{obtentionProcedure}{procedureCode}{id}, 'OHDSI:1004', 'maps specimen_type_concept_id to obtentionProcedure.procedureCode' );
    is( $got->[0]{histologicalDiagnosis}{id}, 'OHDSI:1003', 'maps disease_status_concept_id to histologicalDiagnosis' );
    is( $got->[1]{sampleOriginType}{id}, 'NCIT:C126101', 'defaults sampleOriginType when specimen concept is missing' );
    ok( !exists $got->[1]{sampleOriginDetail}, 'does not synthesize sampleOriginDetail without a concept id' );
    ok( !exists $got->[1]{obtentionProcedure}, 'does not synthesize obtentionProcedure without a concept id' );
    ok( !exists $got->[1]{histologicalDiagnosis}, 'does not synthesize histologicalDiagnosis without a concept id' );
    ok( !exists $got->[0]{notes}, 'does not map specimen_source_value to notes by default' );
    is( $got->[0]{info}{SPECIMEN}{OMOP_columns}{specimen_id}, 901, 'keeps raw specimen provenance' );
}

{
    no warnings 'redefine';

    local *Convert::Pheno::OMOP::ToBFF::Biosamples::map2ohdsi = sub {
        my ($arg) = @_;
        return {
            id    => "OHDSI:$arg->{concept_id}",
            label => "label-$arg->{concept_id}",
        };
    };

    my $self = bless(
        {
            data_ohdsi_dict => {},
            test            => 0,
            metaData        => { created => 'now' },
            convertPheno    => { beaconSchemaVersion => '2.0.0' },
        },
        'Convert::Pheno'
    );
    my $participant = {
        PERSON => {
            person_id      => 5,
            birth_datetime => '1980-01-15 00:00:00',
        },
        SPECIMEN => [
            {
                specimen_id              => 901,
                person_id                => 5,
                specimen_concept_id      => 1001,
                specimen_type_concept_id => 1004,
                specimen_date            => '2020-03-01',
            },
        ],
    };

    my $got = extract_participant_biosamples( $self, $participant, { id => '5' } );
    is(
        $got->[0]{info}{convertPheno}{beaconSchemaVersion},
        '2.0.0',
        'includes Beacon schema version in biosample convertPheno info when not in test mode'
    );
}

{
    my $convert = build_convert();
    my $data = {
        PERSON => [
            {
                person_id         => 1,
                gender_concept_id => 8507,
                birth_datetime    => '1980-01-15 00:00:00',
            },
        ],
        SPECIMEN => [
            {
                specimen_id         => 101,
                person_id           => 1,
                specimen_concept_id => 9001,
            },
            {
                specimen_id         => 102,
                person_id           => 1,
                specimen_concept_id => 9001,
            },
        ],
    };

    my $participants = Convert::Pheno::transpose_omop_data_structure( $convert, $data );
    is( scalar @{ $participants->[0]{SPECIMEN} }, 2, 'non-stream transpose keeps multiple specimen rows per person' );
}

{
    my %files = mimic_specimen_fixture_files();

    my $convert = build_convert(
        in_files  => [ @files{qw(concept person specimen)} ],
        method    => 'omop2bff',
        entities  => [ 'individuals', 'biosamples', 'datasets', 'cohorts' ],
        out_file  => File::Spec->catfile( 't', 'unused-mimic-biosamples.json' ),
        sep       => ';',
    );

    my $bundle = $convert->_run_bundle_view;
    my $sample = find_biosample_by_id(
        $bundle->entities('biosamples'),
        '-5102033398575528989'
    );

    is( scalar @{ $bundle->entities('biosamples') }, 12, 'bundle view emits biosamples from MIMIC SPECIMEN rows' );
    ok( defined $sample, 'bundle biosamples include the expected MIMIC specimen row' );
    is( $sample->{individualId}, '4668337230155062633', 'bundle biosamples keep MIMIC person linkage' );
    is( $sample->{collectionMoment}, 'P44Y', 'bundle biosamples derive collectionMoment from fixture birth date' );
    is( $sample->{obtentionProcedure}{procedureCode}{id}, 'Type Concept:OMOP4976929', 'bundle biosamples map specimen_type_concept_id without ohdsi.db' );
    is( $bundle->entities('datasets')->[0]{info}{biosampleCount}, 12, 'dataset synthesis counts biosamples from the MIMIC fixture' );
    is( $bundle->entities('cohorts')->[0]{cohortSize}, 4, 'cohort synthesis still uses the individuals collection' );
}

{
    my $convert = build_convert(
        in_files => ['t/omop2bff/in/omop_cdm_eunomia.sql'],
        method   => 'omop2bff',
        entities => ['biosamples'],
        out_file => File::Spec->catfile( 't', 'unused-eunomia-biosamples.json' ),
        sep      => ',',
    );

    my $bundle = $convert->_run_bundle_view;
    is_deeply(
        $bundle->entities('biosamples'),
        [],
        'existing OMOP SQL fixture accepts biosamples output when SPECIMEN exists but is empty',
    );
}

{
    my $dir = ensure_clean_dir('t/omop-biosamples-stream-fixture');
    my %files = mimic_specimen_fixture_files();

    my $convert = build_convert(
        in_files => [ @files{qw(concept person specimen)} ],
        method   => 'omop2bff',
        entities => [ 'individuals', 'biosamples' ],
        out_dir  => $dir,
        stream   => 1,
        sep      => ';',
        test     => 1,
    );

    $convert->omop2bff;

    my $individuals = load_json_lines( File::Spec->catfile( $dir, 'individuals.json' ) );
    my $biosamples  = load_json_lines( File::Spec->catfile( $dir, 'biosamples.json' ) );

    is( scalar @{$individuals}, 4, 'stream mode writes one individual line per MIMIC person' );
    is( scalar @{$biosamples}, 12, 'stream mode writes one biosample line per MIMIC specimen row' );
    is( $biosamples->[0]{id}, '-5102033398575528989', 'streamed biosamples keep MIMIC specimen ids' );
    is( $biosamples->[0]{individualId}, '4668337230155062633', 'streamed biosamples keep MIMIC participant linkage' );

    remove_dir_if_exists($dir);
}

{
SKIP: {
        skip "convert-pheno CLI not found at $cli", 12 unless -f $cli;

        my %files = mimic_specimen_fixture_files();

        my $out_dir = ensure_clean_dir('t/omop-biosamples-cli-out');
        my @cmd = (
            $^X,
            $cli,
            '-iomop', @files{qw(concept person specimen)},
            '-obff',
            '--entities', 'biosamples',
            '--out-dir', $out_dir,
            '--sep', ';',
            '--test',
            '-O',
        );

        my $status = system @cmd;
        is( $status, 0, 'CLI writes biosamples from OMOP SPECIMEN in entity-aware mode' );

        my $biosamples_file = File::Spec->catfile( $out_dir, 'biosamples.json' );
        ok( -f $biosamples_file, 'CLI writes biosamples.json for OMOP biosample output' );

    my $biosamples = load_json_file($biosamples_file);
    my $sample = find_biosample_by_id( $biosamples, '-5102033398575528989' );
    is( scalar @{$biosamples}, 12, 'CLI biosamples output contains one entry per MIMIC specimen row' );
    ok( defined $sample, 'CLI biosamples output includes the expected MIMIC specimen id' );
    is( $sample->{collectionMoment}, 'P44Y', 'CLI biosamples output derives collectionMoment from the MIMIC fixture' );
    is( $sample->{obtentionProcedure}{procedureCode}{id}, 'Type Concept:OMOP4976929', 'CLI biosamples map specimen_type_concept_id without ohdsi.db' );

        my $stream_out_dir = ensure_clean_dir('t/omop-biosamples-cli-stream-out');
        my @stream_cmd = (
            $^X,
            $cli,
            '-iomop', @files{qw(concept person specimen)},
            '-obff',
            '--stream',
            '--entities', 'individuals', 'biosamples',
            '--out-dir', $stream_out_dir,
            '--sep', ';',
            '--test',
            '-O',
        );

        my $stream_status = system @stream_cmd;
        is( $stream_status, 0, 'CLI streams OMOP individuals and biosamples together' );

        my $stream_individuals = load_json_lines( File::Spec->catfile( $stream_out_dir, 'individuals.json' ) );
        my $stream_biosamples  = load_json_lines( File::Spec->catfile( $stream_out_dir, 'biosamples.json' ) );
        is( scalar @{$stream_individuals}, 4, 'CLI stream writes MIMIC individuals as line-delimited JSON' );
        is( scalar @{$stream_biosamples}, 12, 'CLI stream writes MIMIC biosamples as line-delimited JSON' );

        my $missing_dir = ensure_clean_dir('t/omop-biosamples-cli-missing-in');
        my %missing_files = write_minimal_omop_inputs( $missing_dir, with_specimen => 0 );
        my $missing_out_dir = ensure_clean_dir('t/omop-biosamples-cli-missing-out');

        my ( $fh, $log_file ) =
          tempfile( DIR => $tmpdir, SUFFIX => '.omop-biosamples.log', UNLINK => 1 );
        my $pid = fork();
        die 'fork failed' unless defined $pid;

        if ( $pid == 0 ) {
            open STDOUT, '>&', $fh or die "dup STDOUT failed: $!";
            open STDERR, '>&', $fh or die "dup STDERR failed: $!";
            exec(
                $^X,
                $cli,
                '-iomop', @missing_files{qw(concept person)},
                '-obff',
                '--entities', 'biosamples',
                '--out-dir', $missing_out_dir,
                '--sep', ';',
                '--test',
                '-O',
            ) or die "exec failed: $!";
        }

        waitpid( $pid, 0 );
        seek $fh, 0, 0;
        local $/;
        my $output = <$fh>;
        close $fh;

        isnt( $? >> 8, 0, 'CLI fails fast when biosamples are requested without SPECIMEN' );
        like(
            $output,
            qr/requires the OMOP table <SPECIMEN>/,
            'CLI prints a focused error for missing SPECIMEN',
        );

        my ( $fh_stream, undef ) =
          tempfile( DIR => $tmpdir, SUFFIX => '.omop-biosamples-stream.log', UNLINK => 1 );
        my $pid_stream = fork();
        die 'fork failed' unless defined $pid_stream;

        if ( $pid_stream == 0 ) {
            open STDOUT, '>&', $fh_stream or die "dup STDOUT failed: $!";
            open STDERR, '>&', $fh_stream or die "dup STDERR failed: $!";
            exec(
                $^X,
                $cli,
                '-iomop', @files{qw(concept person specimen)},
                '-obff',
                '--stream',
                '--entities', 'individuals', 'datasets',
                '--out-dir', $stream_out_dir,
                '--sep', ';',
                '--test',
                '-O',
            ) or die "exec failed: $!";
        }

        waitpid( $pid_stream, 0 );
        seek $fh_stream, 0, 0;
        local $/;
        my $stream_output = <$fh_stream>;
        close $fh_stream;

        isnt( $? >> 8, 0, 'CLI rejects datasets in stream mode' );
        like(
            $stream_output,
            qr/not supported with <--stream>/,
            'CLI prints a focused error for non-streamable entities',
        );

        remove_dir_if_exists($out_dir);
        remove_dir_if_exists($stream_out_dir);
        remove_dir_if_exists($missing_dir);
        remove_dir_if_exists($missing_out_dir);
    }
}

done_testing();
