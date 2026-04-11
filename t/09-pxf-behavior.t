#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use JSON::PP ();
use Test::More;
use Test::ConvertPheno qw(build_convert);

my $wrapped_pxf = {
    phenopacket => {
        subject => {
            id            => 'subject-1',
            sex           => '',
            karyotypicSex => 'UNKNOWN_KARYOTYPE',
        },
        meta_data => {
            created => '2022-01-01T00:00:00Z',
        },
        medical_actions => [
            {
                procedure => {
                    bodySite => { id => 'UBERON:0002107', label => 'liver' },
                },
            },
            {
                treatment => {
                    routeOfAdministration => {
                        id    => 'NCIT:C38288',
                        label => 'Oral Route of Administration',
                    },
                    doseIntervals => [
                        {},
                        {
                            quantity => {
                                unit  => { id => 'NCIT:C28253', label => 'Milligram' },
                                value => 5,
                            },
                        },
                    ],
                },
            },
        ],
        exposures => [
            {
                type       => { id => 'NCIT:C20197', label => 'male' },
                occurrence => { timestamp => '2020-03-04T10:11:12Z' },
            },
        ],
        measurements => [
            {
                assay        => { id => 'LOINC:1234-5', label => 'Example assay' },
                complexValue => {
                    typedQuantities => [
                        {
                            type     => { id => 'NCIT:C25208', label => 'Quantity' },
                            quantity => {
                                unit  => { id => 'NCIT:C28253', label => 'Milligram' },
                                value => 10,
                            },
                        },
                    ],
                },
                timeObserved => { age => { iso8601duration => 'P10Y' } },
            },
        ],
        phenotypicFeatures => [
            {
                type     => { id => 'HP:0000118', label => 'Phenotypic abnormality' },
                negated  => JSON::PP::true,
            },
        ],
        diseases => [
            {
                term     => { id => 'MONDO:0000001', label => 'disease 1' },
                onset    => { age => { iso8601duration => 'P3Y' } },
                excluded => JSON::PP::false,
            },
        ],
        biosamples      => [ { id => 'biosample-1' } ],
        files           => [ { uri => 'file://example' } ],
        interpretations => [ { id => 'interp-1' } ],
        pedigree        => { id => 'ped-1' },
    },
    cohort => { id => 'cohort-1' },
    family => { id => 'family-1' },
};

my $convert = build_convert(
    in_textfile => 0,
    data        => $wrapped_pxf,
    method      => 'pxf2bff',
);

my $got = $convert->pxf2bff;

is( $got->{id}, 'subject-1', 'maps subject id' );
is( $got->{karyotypicSex}, 'UNKNOWN_KARYOTYPE', 'maps karyotypic sex' );
ok( !exists $got->{sex}, 'empty sex is not mapped' );

is( $got->{info}{cohort}{id}, 'cohort-1', 'retains top-level cohort info' );
is( $got->{info}{family}{id}, 'family-1', 'retains top-level family info' );
is( $got->{info}{phenopacket}{metaData}{created}, '2022-01-01T00:00:00Z', 'normalizes meta_data to metaData' );
is( $got->{info}{phenopacket}{biosamples}[0]{id}, 'biosample-1', 'retains biosamples in info' );
is( $got->{info}{phenopacket}{files}[0]{uri}, 'file://example', 'retains files in info' );
is( $got->{info}{phenopacket}{interpretations}[0]{id}, 'interp-1', 'retains interpretations in info' );
is( $got->{info}{phenopacket}{pedigree}{id}, 'ped-1', 'retains pedigree in info' );

is( $got->{diseases}[0]{diseaseCode}{id}, 'MONDO:0000001', 'normalizes disease term to diseaseCode' );
ok( !exists $got->{diseases}[0]{term}, 'removes original disease term key' );
ok( exists $got->{diseases}[0]{ageOfOnset}, 'maps disease onset' );

is( $got->{exposures}[0]{date}, '2020-03-04', 'maps exposure timestamp to date' );
ok( exists $got->{exposures}[0]{unit}, 'adds default unit to exposure' );
ok( exists $got->{exposures}[0]{duration}, 'adds default duration to exposure' );
ok( exists $got->{exposures}[0]{ageAtExposure}, 'adds default ageAtExposure to exposure' );

is( $got->{interventionsOrProcedures}[0]{procedureCode}{id}, 'NCIT:C126101', 'adds default procedure code when missing' );
ok( exists $got->{interventionsOrProcedures}[0]{ageOfProcedure}, 'adds default ageOfProcedure when missing' );

is( $got->{treatments}[0]{treatmentCode}{id}, 'NCIT:C126101', 'adds default treatment code when agent is missing' );
is( $got->{treatments}[0]{doseIntervals}[0]{scheduleFrequency}{id}, 'NCIT:C126101', 'adds default schedule frequency' );
is( $got->{treatments}[0]{doseIntervals}[0]{quantity}{unit}{id}, 'NCIT:C126101', 'adds default quantity' );
is( $got->{treatments}[0]{doseIntervals}[1]{quantity}{value}, 5, 'preserves provided dose quantity' );

is( $got->{measures}[0]{assayCode}{id}, 'LOINC:1234-5', 'maps assay to assayCode' );
is( $got->{measures}[0]{measurementValue}{typedQuantities}[0]{quantityType}{id}, 'NCIT:C25208', 'normalizes complexValue typed quantity type' );
ok( !exists $got->{measures}[0]{complexValue}, 'removes original complexValue key' );
ok( exists $got->{measures}[0]{observationMoment}, 'maps timeObserved to observationMoment' );

is( $got->{phenotypicFeatures}[0]{featureType}{id}, 'HP:0000118', 'maps feature type' );
ok( $got->{phenotypicFeatures}[0]{excluded}, 'maps negated to excluded' );
ok( !exists $got->{phenotypicFeatures}[0]{type}, 'removes original feature type key' );

my $convert_with_tool_info = build_convert(
    in_textfile => 0,
    data        => $wrapped_pxf,
    method      => 'pxf2bff',
    test        => 0,
);

my $got_with_tool_info = $convert_with_tool_info->pxf2bff;
is(
    $got_with_tool_info->{info}{convertPheno}{beaconSchemaVersion},
    '2.0.0',
    'includes Beacon schema version in convertPheno info when not in test mode'
);

done_testing();
