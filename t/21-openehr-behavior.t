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

subtest 'openehr2bff accepts an explicit patient id fallback' => sub {
    my $convert = build_convert(
        method             => 'openehr2bff',
        data               => {
            compositions => [$gender],
        },
        in_textfile        => 0,
        openehr_patient_id => 'fallback-patient',
    );

    my $individual = $convert->openehr2bff;
    is( $individual->{id}, 'fallback-patient', 'uses explicit fallback patient id when the payload has none' );
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

done_testing;
