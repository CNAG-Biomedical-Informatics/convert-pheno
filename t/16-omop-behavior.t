#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use Convert::Pheno::OMOP qw(do_omop2bff);

{
    no warnings 'redefine';

    local *Convert::Pheno::OMOP::ToBFF::Individuals::map2ohdsi = sub {
        my ($arg) = @_;
        my $id = $arg->{concept_id};
        return { id => "OHDSI:$id", label => "label-$id" };
    };

    local *Convert::Pheno::OMOP::ToBFF::Individuals::map_ontology_term = sub {
        my ($arg) = @_;
        return { id => "NCIT:$arg->{query}", label => $arg->{query} };
    };

    local *Convert::Pheno::OMOP::ToBFF::Individuals::map_omop_visit_occurrence = sub {
        my ($arg) = @_;
        return { occurrence_id => $arg->{visit_occurrence_id}, id => "visit-$arg->{visit_occurrence_id}" };
    };

    local *Convert::Pheno::OMOP::ToBFF::Individuals::map_operator_concept_id = sub {
        my ($arg) = @_;
        return {
            low  => -1,
            high => $arg->{value_as_number},
            unit => $arg->{unit},
        };
    };

    my $self = bless(
        {
            data_ohdsi_dict => {},
            exposures       => { 1001 => 1 },
            metaData        => { created => 'x' },
            convertPheno    => { version => 'y' },
            visit_occurrence => { 10 => { visit_occurrence_id => 10 } },
            test            => 0,
            stream          => 0,
        },
        'Convert::Pheno'
    );

    my $participant = {
        PERSON => {
            person_id               => 5,
            birth_datetime          => '2000-01-01 00:00:00',
            gender_concept_id       => 8507,
            race_source_value       => 'African',
            ethnicity_source_value  => 'Spanish',
        },
        CONDITION_OCCURRENCE => [
            {
                person_id                  => 5,
                condition_concept_id       => 2001,
                condition_start_date       => '2010-01-01',
                condition_status_concept_id => 0,
                visit_occurrence_id        => 10,
            },
        ],
        OBSERVATION => [
            {
                person_id               => 5,
                observation_concept_id  => 1001,
                observation_date        => '2015-05-01',
                value_as_number         => '\\N',
                unit_concept_id         => 3001,
                visit_occurrence_id     => 10,
            },
            {
                person_id               => 5,
                observation_concept_id  => 1002,
                observation_date        => '2016-06-01',
                value_as_number         => 12,
                visit_occurrence_id     => 10,
            },
        ],
        PROCEDURE_OCCURRENCE => [
            {
                person_id             => 5,
                procedure_concept_id  => 4001,
                procedure_date        => '2017-07-01',
                visit_occurrence_id   => 10,
            },
        ],
        MEASUREMENT => [
            {
                person_id                   => 5,
                measurement_concept_id      => 5001,
                measurement_date            => '2018-08-01',
                value_as_number             => '\\N',
                value_as_concept_id         => 0,
                measurement_type_concept_id => 6001,
                operator_concept_id         => 0,
                unit_concept_id             => 0,
                visit_occurrence_id         => 10,
            },
            {
                person_id                   => 5,
                measurement_concept_id      => 5002,
                measurement_date            => '2019-09-01',
                value_as_number             => 22,
                value_as_concept_id         => 7001,
                measurement_type_concept_id => 6002,
                operator_concept_id         => 4172756,
                unit_concept_id             => 3002,
                visit_occurrence_id         => 10,
            },
            {
                person_id                   => 5,
                measurement_concept_id      => 0,
                measurement_date            => '2020-10-01',
                value_as_number             => 10,
                value_as_concept_id         => 0,
                measurement_type_concept_id => 6003,
                operator_concept_id         => 0,
                unit_concept_id             => 0,
            },
        ],
        DRUG_EXPOSURE => [
            {
                person_id                 => 5,
                drug_concept_id           => 8001,
                drug_exposure_start_date  => '2021-11-01',
                visit_occurrence_id       => 10,
            },
        ],
    };

    my $got = do_omop2bff( $self, $participant );

    is( $got->{id}, '5', 'maps person id as string' );
    is( $got->{ethnicity}{label}, 'African', 'maps race_source_value to ethnicity' );
    is( $got->{geographicOrigin}{label}, 'Spanish', 'maps ethnicity_source_value to geographicOrigin' );
    ok( exists $got->{info}{metaData}, 'includes metadata when not in test mode' );
    ok( exists $got->{info}{convertPheno}, 'includes convertPheno when not in test mode' );

    is( $got->{diseases}[0]{stage}{id}, 'NCIT:C126101', 'uses default stage when condition status is missing' );
    is( $got->{diseases}[0]{_visit}{occurrence_id}, 10, 'attaches visit info to diseases' );

    is( scalar @{ $got->{exposures} }, 1, 'splits exposure observations from phenotypic features' );
    is( $got->{exposures}[0]{value}, -1, 'maps \\N exposure values to -1' );
    is( $got->{exposures}[0]{unit}{id}, 'OHDSI:3001', 'maps exposure unit when present' );

    is( scalar @{ $got->{phenotypicFeatures} }, 1, 'keeps non-exposure observations as phenotypic features' );
    is( $got->{phenotypicFeatures}[0]{featureType}{id}, 'OHDSI:1002', 'maps phenotypic feature concept' );
    is( $got->{phenotypicFeatures}[0]{_visit}{occurrence_id}, 10, 'attaches visit info to phenotypic features' );

    is( scalar @{ $got->{interventionsOrProcedures} }, 1, 'maps procedures' );
    is( $got->{interventionsOrProcedures}[0]{bodySite}{id}, 'NCIT:C126101', 'uses default procedure body site' );

    is( scalar @{ $got->{measures} }, 2, 'skips measurements with concept_id 0' );
    is( $got->{measures}[0]{measurementValue}{quantity}{value}, -1, 'maps \\N measurement values to default quantity' );
    is( $got->{measures}[1]{measurementValue}{id}, 'OHDSI:7001', 'maps value_as_concept_id when present' );
    is( $got->{measures}[1]{procedure}{procedureCode}{id}, 'OHDSI:6002', 'maps measurement type as procedure code' );
    is( $got->{measures}[1]{_visit}{occurrence_id}, 10, 'attaches visit info to measures' );

    is( scalar @{ $got->{treatments} }, 1, 'maps treatments' );
    is( $got->{treatments}[0]{routeOfAdministration}{id}, 'NCIT:C126101', 'uses default treatment route' );
    is( $got->{treatments}[0]{_visit}{occurrence_id}, 10, 'attaches visit info to treatments' );
}

{
    my $self = bless( { data_ohdsi_dict => {}, stream => 0 }, 'Convert::Pheno' );
    my $participant = { PERSON => { person_id => 1 } };
    is( do_omop2bff( $self, $participant ), undef, 'returns undef when required gender_concept_id is missing' );
}

{
    no warnings 'redefine';
    local *Convert::Pheno::OMOP::ToBFF::Individuals::map2ohdsi = sub { return { id => 'OHDSI:1', label => 'label-1' } };
    local *Convert::Pheno::OMOP::ToBFF::Individuals::map_ontology_term = sub { return { id => 'NCIT:1', label => 'male' } };

    my $self = bless(
        {
            data_ohdsi_dict => {},
            stream          => 1,
            test            => 1,
        },
        'Convert::Pheno'
    );

    my $participant = {
        PERSON => {
            person_id         => 42,
            birth_datetime    => '2000-01-01 00:00:00',
            gender_concept_id => 8507,
        },
    };

    my $first  = do_omop2bff( $self, $participant );
    my $second = do_omop2bff( $self, $participant );
    ok( defined $first, 'stream mode returns the first minimal individual' );
    is( $second, undef, 'stream mode suppresses duplicate minimal individuals' );
}

done_testing();
