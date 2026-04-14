#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use JSON::PP ();
use Test::More;
use Test::Exception;
use Test::Warn;
use Convert::Pheno::BFF::ToOMOP qw(do_bff2omop);

{
    no warnings 'redefine';

    local *Convert::Pheno::BFF::ToOMOP::inverse_map = sub {
        my ( $mapping_type, $hashref, $key, $self ) = @_;
        return ( 9000, $hashref->{$key} // '' );
    };

    my $bff = {
        id   => 123,
        sex  => { label => 'male' },
        info => { dateOfBirth => '2000-01-01T00:00:00Z' },
        diseases => [
            {
                diseaseCode => { label => 'Disease A' },
            },
        ],
        interventionsOrProcedures => [
            {
                procedureCode => { label => 'Procedure A' },
            },
        ],
        measures => [
            {
                assayCode        => { label => 'Scalar measure' },
                measurementValue => 7,
            },
            {
                assayCode => { label => 'Quantity measure' },
                measurementValue => {
                    quantity => {
                        value => 10,
                        unit  => { label => 'Milligram' },
                        referenceRange => {
                            low  => 2,
                            high => 20,
                        },
                    },
                },
                procedure => {
                    procedureCode => { label => 'Procedure B' },
                },
            },
            {
                assayCode => { label => 'Missing value measure' },
            },
        ],
        treatments => [
            {
                treatmentCode => { label => 'Treatment A' },
                routeOfAdministration => { label => 'Route A' },
                ageOfOnset => { age => { iso8601duration => 'P2Y' } },
                cumulativeDose => {
                    unit  => { label => 'week' },
                    value => 2,
                },
            },
            {
                treatmentCode => { label => 'Treatment B' },
                routeOfAdministration => { label => 'Route B' },
                doseIntervals => [
                    {
                        quantity => {
                            value => 5,
                            unit  => { label => 'Milligram' },
                        },
                    },
                ],
                cumulativeDose => {
                    unit  => { label => 'day' },
                    value => 9,
                },
                _visit => { occurrence_id => 77, detail_id => 88 },
            },
            {
                treatmentCode => { label => 'Treatment C' },
                routeOfAdministration => { label => 'Route C' },
                doseIntervals => [
                    {
                        interval => {
                            start => '2005-06-01T00:00:00Z',
                        },
                    },
                ],
            },
        ],
    };

    my $got = do_bff2omop( bless( {}, 'Convert::Pheno' ), $bff );

    is( $got->{PERSON}{person_id}, 123, 'preserves numeric person id' );
    is( $got->{PERSON}{year_of_birth}, '2000', 'extracts year of birth' );
    is( $got->{CONDITION_OCCURRENCE}[0]{condition_start_date}, '1900-01-01', 'uses default disease date without ageOfOnset' );
    is( $got->{PROCEDURE_OCCURRENCE}[0]{procedure_date}, '1900-01-01', 'uses default procedure date when missing' );
    is( $got->{PROCEDURE_OCCURRENCE}[0]{procedure_datetime}, '1900-01-01T00:00:00Z', 'uses default procedure timestamp when missing' );

    is( $got->{MEASUREMENT}[0]{value_as_number}, 7, 'maps scalar measurement value' );
    is( $got->{MEASUREMENT}[0]{measurement_type_concept_id}, 0, 'uses default measurement type without procedure' );
    is( $got->{MEASUREMENT}[1]{value_as_number}, 10, 'maps quantity measurement value' );
    is( $got->{MEASUREMENT}[1]{range_low}, 2, 'maps quantity reference low' );
    is( $got->{MEASUREMENT}[1]{range_high}, 20, 'maps quantity reference high' );
    is( $got->{MEASUREMENT}[1]{measurement_type_concept_id}, 9000, 'maps measurement procedure when present' );
    is( $got->{MEASUREMENT}[2]{value_as_number}, -1, 'defaults missing measurement value to -1' );

    is( $got->{DRUG_EXPOSURE}[0]{drug_exposure_start_date}, '2002-01-01', 'derives treatment start date from ageOfOnset' );
    is( $got->{DRUG_EXPOSURE}[0]{drug_exposure_end_date}, '2002-01-01', 'defaults treatment end date to start date' );
    is( $got->{DRUG_EXPOSURE}[0]{quantity}, -1, 'defaults treatment quantity when doseIntervals are missing' );
    is( $got->{DRUG_EXPOSURE}[0]{days_supply}, 14, 'derives days supply from cumulativeDose value and unit' );
    is( $got->{DRUG_EXPOSURE}[1]{drug_exposure_start_date}, '1900-01-01', 'falls back to the default treatment start date when doseIntervals lack interval dates' );
    is( $got->{DRUG_EXPOSURE}[1]{drug_exposure_end_date}, '1900-01-01', 'falls back to the default treatment end date when doseIntervals lack interval dates' );
    is( $got->{DRUG_EXPOSURE}[1]{quantity}, 5, 'uses first dose interval quantity when present' );
    is( $got->{DRUG_EXPOSURE}[1]{days_supply}, 9, 'uses cumulativeDose duration rather than dose quantity for days supply' );
    is( $got->{DRUG_EXPOSURE}[1]{visit_occurrence_id}, 77, 'attaches visit occurrence id' );
    is( $got->{DRUG_EXPOSURE}[1]{visit_detail_id}, 88, 'attaches visit detail id' );
    is( $got->{DRUG_EXPOSURE}[2]{drug_exposure_start_date}, '2005-06-01', 'maps treatment start date from dose interval start timestamp' );
    is( $got->{DRUG_EXPOSURE}[2]{drug_exposure_end_date}, '2005-06-01', 'reuses the available dose interval date for treatment end date when end is missing' );
}

{
    no warnings 'redefine';

    local *Convert::Pheno::BFF::ToOMOP::inverse_map = sub {
        my ( $mapping_type, $hashref, $key, $self ) = @_;
        return ( 9000, $hashref->{$key} // '' );
    };

    my $bff = {
        id   => 'subject-a',
        sex  => { label => 'male' },
        info => { dateOfBirth => '2000-01-01T00:00:00Z' },
        diseases => [
            {
                diseaseCode => { label => 'Disease A' },
                _visit      => {
                    occurrence_id => 'visit-alpha',
                    composite     => 'subject-a.week-0',
                },
            },
        ],
        treatments => [
            {
                treatmentCode => { label => 'Treatment A' },
                routeOfAdministration => { label => 'Route A' },
                _visit => {
                    occurrence_id => 'visit-alpha',
                    composite     => 'subject-a.week-0',
                },
            },
        ],
    };

    my $got = do_bff2omop( bless( {}, 'Convert::Pheno' ), $bff );

    is( $got->{PERSON}{person_id}, 1, 'allocates a surrogate numeric person id for nonnumeric ids' );
    is( $got->{PERSON}{person_source_value}, 'subject-a', 'preserves original person id in person_source_value' );
    is( $got->{CONDITION_OCCURRENCE}[0]{visit_occurrence_id}, 1, 'allocates a surrogate numeric visit id for nonnumeric visit ids' );
    is( $got->{DRUG_EXPOSURE}[0]{visit_occurrence_id}, 1, 'reuses the same surrogate visit id for the same composite visit key' );
}

warning_like {
    my @result = Convert::Pheno::BFF::ToOMOP::inverse_map(
        'unknown',
        { label => 'x' },
        'label',
        undef,
    );
    is_deeply( \@result, [ 0, '' ], 'unknown inverse mapping falls back to zeros' );
} qr/Unknown mapping type <unknown>/, 'inverse_map warns on unknown mapping type';

dies_ok {
    do_bff2omop( bless( {}, 'Convert::Pheno' ), { subject => { id => 'pxf-like' } } );
} 'do_bff2omop dies on non-BFF input';

is( do_bff2omop( bless( {}, 'Convert::Pheno' ), undef ), undef, 'do_bff2omop returns undef on missing input' );

done_testing();
