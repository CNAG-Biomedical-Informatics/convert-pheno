#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;

use Convert::Pheno::Context;
use Convert::Pheno::Model::Bundle;
use Convert::Pheno::OMOP::ToBFF qw(do_omop2bff run_omop_to_bundle map_participant extract_participant_biosamples);
use Convert::Pheno::PXF::ToBFF qw(do_pxf2bff run_pxf_to_bundle map_pxf_to_individual map_pxf_to_biosample);

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
    is_deeply( $bundle->primary_entity('individuals'), { id => 'i1' }, 'bundle exposes primary entity view' );
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

    my $primary = do_omop2bff( $convert, $participant );
    is_deeply( $primary, { id => 7 }, 'do_omop2bff unwraps the bundle to the primary result' );
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
    my $biosample = map_pxf_to_biosample(
        bless( {}, 'Convert::Pheno' ),
        {
            id                    => 'bio-1',
            individualId          => 'p1',
            description           => 'source note',
            materialSample        => { id => 'EFO:0009655', label => 'abnormal sample' },
            sampleType            => { id => 'EFO:0008479', label => 'genomic DNA' },
            sampledTissue         => { id => 'UBERON:0001256', label => 'wall of urinary bladder' },
            tumorProgression      => { id => 'NCIT:C84509', label => 'Primary Malignant Neoplasm' },
            tumorGrade            => { id => 'NCIT:C36136', label => 'Grade 2 Lesion' },
            histologicalDiagnosis => { id => 'NCIT:C39853', label => 'Infiltrating Urothelial Carcinoma' },
            diagnosticMarkers     => [ { id => 'NCIT:C131711', label => 'Human Papillomavirus-18 Positive' } ],
            pathologicalStage     => { id => 'NCIT:C28054', label => 'Stage II' },
            pathologicalTnmFinding => [ { id => 'NCIT:C48726', label => 'T2b Stage Finding' } ],
            timeOfCollection      => {
                age       => { iso8601duration => 'P52Y2M' },
                timestamp => '2021-04-23T00:00:00Z',
            },
            procedure => {
                code      => { id => 'NCIT:C5189', label => 'Radical Cystoprostatectomy' },
                bodySite  => { id => 'UBERON:0001256', label => 'wall of urinary bladder' },
                performed => { timestamp => '2021-04-23T00:00:00Z' },
            },
            phenotypicFeatures => [
                {
                    type     => { id => 'NCIT:C35941', label => 'Flexner-Wintersteiner Rosette Formation' },
                    excluded => 0,
                    evidence => [
                        {
                            evidenceCode => { id => 'ECO:0000033', label => 'author statement supported by traceable reference' },
                            reference    => { id => 'PMID:123', description => 'paper title' },
                        }
                    ],
                }
            ],
            measurements => [
                {
                    assay        => { id => 'LOINC:33728-7', label => 'Size.maximum dimension in Tumor' },
                    value        => { quantity => { unit => { id => 'UCUM:mm', label => 'millimeter' }, value => 15 } },
                    timeObserved => { age => { iso8601duration => 'P8M2W' } },
                }
            ],
            files => [ { uri => 'file://x.vcf.gz' } ],
            taxonomy => { id => 'NCBITaxon:9606', label => 'Homo sapiens' },
        },
        'fallback-individual'
    );

    is( $biosample->{id}, 'bio-1', 'biosample mapper keeps biosample id' );
    is( $biosample->{individualId}, 'p1', 'biosample mapper keeps individualId' );
    is_deeply( $biosample->{biosampleStatus}, { id => 'EFO:0009655', label => 'abnormal sample' }, 'biosample mapper maps materialSample to biosampleStatus' );
    is_deeply( $biosample->{sampleOriginType}, { id => 'EFO:0008479', label => 'genomic DNA' }, 'biosample mapper maps sampleType to sampleOriginType' );
    is_deeply( $biosample->{sampleOriginDetail}, { id => 'UBERON:0001256', label => 'wall of urinary bladder' }, 'biosample mapper maps sampledTissue to sampleOriginDetail' );
    is( $biosample->{collectionMoment}, 'P52Y2M', 'biosample mapper maps age-at-collection to collectionMoment' );
    is( $biosample->{collectionDate}, '2021-04-23', 'biosample mapper maps timestamp to collectionDate' );
    is_deeply( $biosample->{obtentionProcedure}{procedureCode}, { id => 'NCIT:C5189', label => 'Radical Cystoprostatectomy' }, 'biosample mapper renames procedure.code' );
    is( $biosample->{obtentionProcedure}{dateOfProcedure}, '2021-04-23', 'biosample mapper derives procedure date' );
    is_deeply( $biosample->{phenotypicFeatures}[0]{featureType}, { id => 'NCIT:C35941', label => 'Flexner-Wintersteiner Rosette Formation' }, 'biosample mapper renames phenotypic feature type' );
    is( $biosample->{phenotypicFeatures}[0]{evidence}[0]{reference}{notes}, 'paper title', 'biosample mapper renames evidence reference description to notes' );
    is_deeply( $biosample->{measurements}[0]{assayCode}, { id => 'LOINC:33728-7', label => 'Size.maximum dimension in Tumor' }, 'biosample mapper renames assay to assayCode' );
    is_deeply( $biosample->{measurements}[0]{measurementValue}{quantity}{unit}, { id => 'UCUM:mm', label => 'millimeter' }, 'biosample mapper renames measurement value' );
    ok( exists $biosample->{info}{phenopacket}{files}, 'biosample mapper preserves non-Beacon files under info' );
    ok( exists $biosample->{info}{phenopacket}{taxonomy}, 'biosample mapper preserves taxonomy under info' );
}

{
    my $biosample = map_pxf_to_biosample(
        bless( {}, 'Convert::Pheno' ),
        {
            id => 'bio-2',
        },
        'fallback-individual'
    );

    is( $biosample->{individualId}, 'fallback-individual', 'biosample mapper falls back to parent individualId' );
    is_deeply( $biosample->{biosampleStatus}, { id => 'NCIT:C126101', label => 'Not Available' }, 'biosample mapper defaults biosampleStatus for validation' );
    is_deeply( $biosample->{sampleOriginType}, { id => 'NCIT:C126101', label => 'Not Available' }, 'biosample mapper defaults sampleOriginType for validation' );
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
        $bundle->entities('biosamples')->[0]{individualId},
        'pxf-1',
        'run_pxf_to_bundle includes requested biosamples in the bundle'
    );
    is_deeply(
        $bundle->entities('biosamples')->[0]{biosampleStatus},
        { id => 'NCIT:C126101', label => 'Not Available' },
        'run_pxf_to_bundle applies biosample defaults in bundle mode'
    );

    my $primary = do_pxf2bff( $convert, $pxf );
    is_deeply( $primary, { id => 'pxf-1' }, 'do_pxf2bff unwraps the bundle to the primary result' );
}

done_testing();
