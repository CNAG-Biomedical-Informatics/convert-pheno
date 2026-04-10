#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;

use Convert::Pheno::Context;
use Convert::Pheno::Model::Bundle;
use Convert::Pheno::OMOP::ToBFF qw(do_omop2bff run_omop_to_bundle map_participant extract_participant_biosamples);
use Convert::Pheno::PXF::ToBFF qw(do_pxf2bff run_pxf_to_bundle map_pxf_to_individual);

{
    my $convert = bless(
        {
            method          => 'omop2bff',
            method_ori      => 'omop2bff',
            stream          => 0,
            test            => 1,
            verbose         => 0,
            debug           => 0,
            metaData        => { created => 'now' },
            convertPheno    => { version => 'x' },
            data_ohdsi_dict => {},
            exposures       => {},
        },
        'Convert::Pheno'
    );

    my $context = Convert::Pheno::Context->from_self(
        $convert,
        {
            source_format => 'omop',
            target_format => 'beacon',
            entities      => ['individuals'],
        }
    );

    is( $context->source_format, 'omop', 'context stores source format' );
    is( $context->target_format, 'beacon', 'context stores target format' );
    is_deeply( $context->entities, ['individuals'], 'context stores requested entities' );
    is( $context->options->{method}, 'omop2bff', 'context stores execution options' );
    is( $context->resources->{metaData}{created}, 'now', 'context stores resources' );
}

{
    my $bundle = Convert::Pheno::Model::Bundle->new(
        {
            entities => [ 'individuals', 'biosamples' ],
        }
    );

    ok( $bundle->add_entity( individuals => { id => 'i1' } ), 'bundle accepts individuals' );
    is_deeply( $bundle->entities('individuals'), [ { id => 'i1' } ], 'bundle stores entity arrays' );
    is_deeply( $bundle->entities('biosamples'), [], 'bundle preinitializes requested entity arrays' );
    is_deeply( $bundle->legacy_primary_entity('individuals'), { id => 'i1' }, 'bundle exposes legacy primary entity view' );
}

{
    no warnings 'redefine';

    local *Convert::Pheno::OMOP::ToBFF::map_participant = sub {
        my ( $self, $participant ) = @_;
        return { id => $participant->{PERSON}{person_id} };
    };

    my $convert = bless(
        {
            conversion_context => Convert::Pheno::Context->new(
                {
                    source_format => 'omop',
                    target_format => 'beacon',
                    entities      => ['individuals'],
                }
            ),
        },
        'Convert::Pheno'
    );

    my $participant = { PERSON => { person_id => 7, gender_concept_id => 8507 } };

    my $bundle = run_omop_to_bundle( $convert, $participant, $convert->{conversion_context} );
    is_deeply( $bundle->entities('individuals'), [ { id => 7 } ], 'run_omop_to_bundle builds a bundle' );

    my $legacy = do_omop2bff( $convert, $participant );
    is_deeply( $legacy, { id => 7 }, 'do_omop2bff unwraps the bundle to the legacy result' );
}

{
    no warnings 'redefine';

    local *Convert::Pheno::OMOP::ToBFF::map_participant = sub {
        my ( $self, $participant ) = @_;
        return { id => $participant->{PERSON}{person_id} };
    };
    local *Convert::Pheno::OMOP::ToBFF::extract_participant_biosamples = sub {
        my ( $self, $participant, $individual ) = @_;
        return [];
    };

    my $convert = bless(
        {
            conversion_context => Convert::Pheno::Context->new(
                {
                    source_format => 'omop',
                    target_format => 'beacon',
                    entities      => [ 'individuals', 'biosamples' ],
                }
            ),
        },
        'Convert::Pheno'
    );

    my $participant = { PERSON => { person_id => 8, gender_concept_id => 8507 } };

    my $bundle = run_omop_to_bundle( $convert, $participant, $convert->{conversion_context} );
    is_deeply( $bundle->entities('individuals'), [ { id => 8 } ], 'run_omop_to_bundle still builds OMOP individuals in multi-entity mode' );
    is_deeply( $bundle->entities('biosamples'), [], 'run_omop_to_bundle preps OMOP biosamples as an empty placeholder entity' );
}

{
    no warnings 'redefine';

    local *Convert::Pheno::PXF::ToBFF::map_pxf_to_individual = sub {
        my ( $self, $phenopacket, $cohort, $family ) = @_;
        return { id => $phenopacket->{subject}{id} };
    };
    local *Convert::Pheno::PXF::ToBFF::validate_format = sub { return 1 };

    my $convert = bless(
        {
            conversion_context => Convert::Pheno::Context->new(
                {
                    source_format => 'pxf',
                    target_format => 'beacon',
                    entities      => [ 'individuals', 'biosamples' ],
                }
            ),
        },
        'Convert::Pheno'
    );

    my $pxf = {
        subject => {
            id => 'pxf-1',
        },
        biosamples => [
            { id => 'bio-1' },
        ],
    };

    my $bundle = run_pxf_to_bundle( $convert, $pxf, $convert->{conversion_context} );
    is_deeply( $bundle->entities('individuals'), [ { id => 'pxf-1' } ], 'run_pxf_to_bundle builds a bundle' );
    is_deeply(
        $bundle->entities('biosamples'),
        [ { id => 'bio-1', individualId => 'pxf-1' } ],
        'run_pxf_to_bundle includes requested biosamples in the bundle'
    );

    my $legacy = do_pxf2bff( $convert, $pxf );
    is_deeply( $legacy, { id => 'pxf-1' }, 'do_pxf2bff unwraps the bundle to the legacy result' );
}

done_testing();
