#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use Test::ConvertPheno qw(
  build_convert
  load_json_file
  temp_output_file
  write_json_file
  structured_files_match
);

my $gender = load_json_file('t/openehr2bff/in/gecco_personendaten.json');
my $ips    = load_json_file('t/openehr2bff/in/ips_canonical.json');
my $lab    = load_json_file('t/openehr2bff/in/laboratory_report.json');
my $corona = load_json_file('t/openehr2bff/in/compo_corona.json');

sub with_subject_id {
    my ( $composition, $id ) = @_;
    my %copy = %{$composition};
    $copy{subject} = {
        _type        => 'PARTY_SELF',
        external_ref => {
            id        => { _type => 'GENERIC_ID', value => $id, scheme => 'PMI' },
            namespace => 'PMI',
            type      => 'PERSON',
        },
    };
    return \%copy;
}

subtest 'openehr2bff aggregates canonical compositions into one individual' => sub {
    my $convert = build_convert(
        method      => 'openehr2bff',
        data        => {
            patient      => { id => 'openehr-patient-1' },
            compositions => [ $gender, $ips ],
        },
        in_textfile => 0,
    );

    my $individual = $convert->openehr2bff;

    is( $individual->{id}, 'openehr-patient-1', 'uses patient id from the envelope' );
    is( $individual->{sex}{id}, 'NCIT:C20197', 'maps administrative gender to Beacon sex term' );
    is( scalar @{ $individual->{info}{openehr}{compositions} }, 2, 'preserves all source compositions under info.openehr' );
};

subtest 'openehr2bff emits first-class arrays from multiple canonical compositions' => sub {
    my $convert = build_convert(
        method      => 'openehr2bff',
        data        => {
            patient      => { id => 'openehr-patient-2' },
            compositions => [ $gender, $ips, $lab, $corona ],
        },
        in_textfile => 0,
    );

    my $individual = $convert->openehr2bff;

    is( scalar @{ $individual->{diseases} }, 3, 'maps problem diagnosis entries to diseases' );
    is( scalar @{ $individual->{measures} }, 2, 'maps multiple observations with values to measures' );
    is( scalar @{ $individual->{phenotypicFeatures} }, 7, 'maps symptom screening observations to phenotypicFeatures' );
    is( scalar @{ $individual->{interventionsOrProcedures} }, 1, 'maps procedure actions to interventionsOrProcedures' );
    is( scalar @{ $individual->{treatments} }, 2, 'maps medication actions to treatments' );

    my ($loinc_measure) = grep {
        exists $_->{assayCode}
          && ref( $_->{assayCode} ) eq 'HASH'
          && exists $_->{assayCode}{id}
          && $_->{assayCode}{id} eq 'LOINC:2093-3'
    } @{ $individual->{measures} };

    ok( defined $loinc_measure, 'keeps coded laboratory observations as first-class measures' );
    is( $loinc_measure->{measurementValue}{quantity}{value}, 203, 'preserves numeric result values for coded lab measures' );

    my ($present_feature) = grep { exists $_->{excluded} && $_->{excluded} == 0 }
      @{ $individual->{phenotypicFeatures} };
    my ($absent_feature) = grep { exists $_->{excluded} && $_->{excluded} == 1 }
      @{ $individual->{phenotypicFeatures} };

    ok( defined $present_feature, 'marks present symptoms as non-excluded phenotypic features' );
    ok( defined $absent_feature, 'marks absent symptoms as excluded phenotypic features' );

    my $tmp_file = temp_output_file( suffix => '.json', dir => 't' );
    write_json_file( $tmp_file, [$individual] );
    ok(
        structured_files_match( 't/openehr2bff/out/individuals.json', $tmp_file ),
        'matches the openEHR fixture snapshot'
    );
};

subtest 'openehr2bff accepts openEHR ehr_id and ehr_status patient identifiers' => sub {
    {
        my $convert = build_convert(
            method      => 'openehr2bff',
            data        => {
                ehr_id       => { value => 'ehr-123' },
                compositions => [$gender],
            },
            in_textfile => 0,
        );

        my $individual = $convert->openehr2bff;
        is( $individual->{id}, 'ehr-123', 'uses ehr_id.value when present in the payload envelope' );
    }

    {
        my $convert = build_convert(
            method      => 'openehr2bff',
            data        => {
                ehr_id       => { value => 'ehr-123' },
                ehr_status   => {
                    subject => {
                        _type        => 'PARTY_SELF',
                        external_ref => {
                            id        => { _type => 'GENERIC_ID', value => 'subject-456', scheme => 'PMI' },
                            namespace => 'PMI',
                            type      => 'PERSON',
                        },
                    },
                },
                compositions => [$gender],
            },
            in_textfile => 0,
        );

        my $individual = $convert->openehr2bff;
        is( $individual->{id}, 'subject-456', 'prefers ehr_status.subject.external_ref.id.value over ehr_id when both are present' );
    }
};

subtest 'openehr2bff accepts PARTY_SELF external_ref identifiers inside compositions' => sub {
    my $gender_with_subject = load_json_file('t/openehr2bff/in/gecco_personendaten.json');
    $gender_with_subject->{subject} = {
        _type        => 'PARTY_SELF',
        external_ref => {
            id        => { _type => 'GENERIC_ID', value => 'subject-789', scheme => 'PMI' },
            namespace => 'PMI',
            type      => 'PERSON',
        },
    };

    my $convert = build_convert(
        method      => 'openehr2bff',
        data        => { compositions => [$gender_with_subject] },
        in_textfile => 0,
    );

    my $individual = $convert->openehr2bff;
    is( $individual->{id}, 'subject-789', 'uses PARTY_SELF.external_ref.id.value when present in a composition' );
};

subtest 'openehr2bff fails clearly when patient id cannot be resolved' => sub {
    my $convert = build_convert(
        method      => 'openehr2bff',
        data        => { compositions => [$gender] },
        in_textfile => 0,
    );

    my $ok = eval { $convert->openehr2bff; 1 };
    ok( !$ok, 'conversion failed' );
    like( $@, qr/patient id/i, 'error mentions missing patient id' );
};

subtest 'openehr2bff groups multiple patients before mapping' => sub {
    my $patient_a = with_subject_id( $gender, 'patient-a' );
    my $patient_b = with_subject_id( $gender, 'patient-b' );

    my $convert = build_convert(
        method      => 'openehr2bff',
        data        => [
            { compositions => [$patient_a] },
            { compositions => [$patient_b] },
        ],
        in_textfile => 0,
    );

    my $individuals = $convert->openehr2bff;
    is( ref($individuals), 'ARRAY', 'returns an array for multi-patient openEHR input' );
    is( scalar @{$individuals}, 2, 'emits one individual per patient bucket' );
    is_deeply(
        [ map { $_->{id} } @{$individuals} ],
        [ 'patient-a', 'patient-b' ],
        'keeps deterministic patient ordering'
    );
    is( $individuals->[0]{sex}{id}, 'NCIT:C20197', 'maps first patient sex' );
    is( $individuals->[1]{sex}{id}, 'NCIT:C20197', 'maps second patient sex' );
};

subtest 'openehr2bff splits raw composition arrays when distinct patient ids are embedded per composition' => sub {
    my $patient_a = with_subject_id( $gender, 'patient-a' );
    my $patient_b = with_subject_id( $gender, 'patient-b' );

    my $convert = build_convert(
        method      => 'openehr2bff',
        data        => [ $patient_a, $patient_b ],
        in_textfile => 0,
    );

    my $individuals = $convert->openehr2bff;
    is( ref($individuals), 'ARRAY', 'returns an array for mixed-patient raw composition input' );
    is_deeply(
        [ map { $_->{id} } @{$individuals} ],
        [ 'patient-a', 'patient-b' ],
        'splits raw composition arrays by embedded patient id'
    );
};

subtest 'openehr2bff does not split raw composition arrays by composition-level ids' => sub {
    my $patient_a = with_subject_id( $gender, 'patient-a' );
    my $patient_b = with_subject_id( $ips,    'patient-a' );
    $patient_a->{id} = 'composition-a';
    $patient_b->{id} = 'composition-b';

    my $convert = build_convert(
        method      => 'openehr2bff',
        data        => [ $patient_a, $patient_b ],
        in_textfile => 0,
    );

    my $individual = $convert->openehr2bff;
    is( ref($individual), 'HASH', 'keeps one individual when embedded patient id is the same' );
    is( $individual->{id}, 'patient-a', 'uses embedded patient id instead of composition ids' );
};

done_testing;
