#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use JSON::PP ();
use Test::More;
use File::Temp qw(tempdir tempfile);
use Convert::Pheno::IO::CSVHandler qw(
  convert_table_aoh_to_hoh
  get_headers
  load_exposures
  open_filehandle
  read_csv
  read_redcap_dict_file
  transpose_omop_data_structure
);

{
    my $self = bless { debug => 0, verbose => 0 }, 'Convert::Pheno';
    my $data = {
        PERSON => [
            { person_id => 2, gender_concept_id => 1 },
            { person_id => 1, gender_concept_id => 2 },
        ],
        MEASUREMENT => [
            { person_id => 2, measurement_concept_id => 10 },
            { person_id => 2, measurement_concept_id => 11 },
        ],
        OBSERVATION => [],
        CONDITION_OCCURRENCE => [],
        PROCEDURE_OCCURRENCE => [],
        DRUG_EXPOSURE => [],
        VISIT_OCCURRENCE => [],
        CONCEPT => [],
    };

    my $aoh = transpose_omop_data_structure( $self, $data );
    is( scalar @$aoh, 2, 'transpose_omop_data_structure returns one entry per person' );
    is( $aoh->[0]{PERSON}{person_id}, 1, 'transpose_omop_data_structure sorts by person_id' );
    is( scalar @{ $aoh->[1]{MEASUREMENT} }, 2, 'transpose_omop_data_structure keeps array tables grouped' );
}

{
    my $data = {
        CONCEPT => [
            { concept_id => 10, concept_name => 'Ten' },
            { concept_id => 20, concept_name => 'Twenty' },
        ],
        PERSON => [
            { person_id => 1, gender_concept_id => 8507 },
            { person_id => 2, gender_concept_id => 8532 },
        ],
        VISIT_OCCURRENCE => [
            { visit_occurrence_id => 5, person_id => 1 },
        ],
    };

    my $concept = convert_table_aoh_to_hoh( $data, 'CONCEPT', {} );
    is( $concept->{10}{concept_name}, 'Ten', 'convert_table_aoh_to_hoh indexes CONCEPT by concept_id' );
    is( scalar @{ $data->{CONCEPT} }, 0, 'convert_table_aoh_to_hoh drains the source array for CONCEPT' );

    my $person = convert_table_aoh_to_hoh( $data, 'PERSON', {} );
    is( $person->{2}{gender_concept_id}, 8532, 'convert_table_aoh_to_hoh indexes PERSON by person_id' );

    my $visit = convert_table_aoh_to_hoh( $data, 'VISIT_OCCURRENCE', {} );
    is( $visit->{5}{person_id}, 1, 'convert_table_aoh_to_hoh indexes VISIT_OCCURRENCE by visit_occurrence_id' );
}

{
    my $headers = get_headers(
        [
            { alpha => 1, beta => 2, nested => { ignore => 1 } },
            { beta => 3, gamma => 4 },
        ]
    );
    is_deeply( $headers, [ 'alpha', 'beta', 'gamma' ], 'get_headers collects scalar keys and skips nested refs' );
}

{
    my $tmpdir = tempdir( CLEANUP => 1 );
    my $file = "$tmpdir/exposures.tsv";
    open my $fh, '>', $file or die $!;
    print {$fh} "concept_id\tlabel\n101\tAlpha\n202\tBeta\n";
    close $fh;

    my $exposures = load_exposures($file);
    is_deeply( $exposures, { 101 => 1, 202 => 1 }, 'load_exposures returns concept_id lookup hash' );
}

{
    my $tmpdir = tempdir( CLEANUP => 1 );
    my $plain = "$tmpdir/plain.txt";
    my $gz    = "$tmpdir/plain.txt.gz";

    my $fh_plain = open_filehandle( $plain, 'w' );
    print {$fh_plain} "hello\n";
    close $fh_plain;

    my $fh_plain_r = open_filehandle( $plain, 'r' );
    my $plain_content = do { local $/; <$fh_plain_r> };
    close $fh_plain_r;
    is( $plain_content, "hello\n", 'open_filehandle reads plain files' );

    my $fh_gz = open_filehandle( $gz, 'w' );
    print {$fh_gz} "hello-gz\n";
    close $fh_gz;

    my $fh_gz_r = open_filehandle( $gz, 'r' );
    my $gz_content = do { local $/; <$fh_gz_r> };
    close $fh_gz_r;
    is( $gz_content, "hello-gz\n", 'open_filehandle reads gzipped files' );
}

{
    my $tmpdir = tempdir( CLEANUP => 1 );
    my $gz = "$tmpdir/redcap_dictionary.csv.gz";

    my $fh = open_filehandle( $gz, 'w' );
    print {$fh}
      "Variable / Field Name;Choices, Calculations, OR Slider Labels;Field Label\n";
    print {$fh} "sex;1, Male | 2, Female;Sex\n";
    close $fh;

    my $dict = read_redcap_dict_file( { redcap_dictionary => $gz } );
    is( $dict->field_label('sex'), 'Sex', 'read_redcap_dict_file reads gzipped REDCap dictionaries into a dictionary object' );
    is( $dict->choice_label( 'sex', 1 ), 'Male', 'read_redcap_dict_file populates labels from gzipped REDCap dictionaries' );
    is( $dict->choice_label( 'sex', 2 ), 'Female', 'read_redcap_dict_file preserves all label mappings from gzipped REDCap dictionaries' );
}

{
    my $tmpdir = tempdir( CLEANUP => 1 );
    my $file = "$tmpdir/redcap_dictionary_complex.csv";

    my $fh = open_filehandle( $file, 'w' );
    print {$fh}
      "Variable / Field Name;Choices, Calculations, OR Slider Labels;Field Label\n";
    print {$fh}
      "severity;1, Mild, moderate symptoms | 2, Severe symptoms;Severity\n";
    print {$fh}
      "calc;[foo]+[bar];Calculated field\n";
    close $fh;

    my $dict = read_redcap_dict_file( { redcap_dictionary => $file } );
    is(
        $dict->choice_label( 'severity', 1 ),
        'Mild, moderate symptoms',
        'read_redcap_dict_file preserves commas inside REDCap choice labels',
    );
    is(
        $dict->choice_label( 'severity', 2 ),
        'Severe symptoms',
        'read_redcap_dict_file still parses later REDCap choice labels',
    );
    ok(
        !$dict->has_choice_labels('calc'),
        'read_redcap_dict_file leaves non-choice REDCap dictionary content unparsed',
    );
}

{
    my $tmpdir = tempdir( CLEANUP => 1 );
    my $file = "$tmpdir/raw.csv";
    open my $fh, '>', $file or die $!;
    print {$fh} "id;decimal;code\n";
    print {$fh} "00123;12,5;A01\n";
    close $fh;

    my $coerced = read_csv( { in => $file, sep => ';' } );
    is( $coerced->[0]{id}, 123, 'read_csv coerces numeric-looking identifiers by default' );
    is( $coerced->[0]{decimal}, 12.5, 'read_csv normalizes locale-style decimals in coercing mode' );

    my $raw = read_csv( { in => $file, sep => ';', coerce_numbers => 0 } );
    is( $raw->[0]{id}, '00123', 'read_csv can preserve leading-zero identifiers in raw-string mode' );
    is( $raw->[0]{decimal}, '12,5', 'read_csv raw-string mode preserves original scalar text' );
}

done_testing();
