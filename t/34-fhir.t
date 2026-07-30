#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use JSON::XS;
use Storable qw(dclone);
use Test::Exception;
use Test::More;

use Convert::Pheno;
use Convert::Pheno::Source qw(source_adapter);
use Test::ConvertPheno qw(load_json_file);

my $fixture_file = 't/fhir2bff/in/patient-bundle.json';
my $fixture      = load_json_file($fixture_file);
my $patient_id   = '5b24c87b-6223-f5b4-51e9-82051159bd1d';

{
    my $convert = Convert::Pheno->new(
        {
            method   => 'fhir2bff',
            in_files => [$fixture_file],
            test     => 1,
        }
    );
    my $source = source_adapter( $convert, 'fhir' )->load;

    is( scalar @{ $source->data }, 1, 'FHIR source emits one patient bucket' );
    is( $source->data->[0]{id}, $patient_id, 'FHIR source retains the Patient id' );
    is(
        scalar @{ $source->data->[0]{resources} },
        9,
        'FHIR source associates every patient-scoped resource across reference forms'
    );
    is(
        $source->artifact('bundle_metadata')->[0]{type},
        'collection',
        'FHIR source exposes Bundle metadata'
    );
    is(
        $source->artifact('derived_entity_overrides')->{datasets}{id},
        'research-study-1',
        'FHIR ResearchStudy prepopulates derived dataset metadata'
    );
    is(
        $source->artifact('derived_entity_overrides')->{cohorts}{id},
        'research-cohort-1',
        'FHIR Group prepopulates derived cohort metadata'
    );
    ok( $source->owned, 'normalized FHIR patient buckets are adapter-owned' );
}

{
    my $convert = Convert::Pheno->new(
        {
            method   => 'fhir2bff',
            in_files => [$fixture_file],
            test     => 1,
        }
    );
    my $individuals = $convert->fhir2bff;
    my $expected    = load_json_file('t/fhir2bff/out/individuals.json');

    is_deeply( $individuals, $expected, 'fhir2bff matches the validated fixture' );
    is(
        $individuals->[0]{diseases}[0]{diseaseCode}{id},
        'SNOMEDCT:307426000',
        'FHIR Condition maps its coding to a disease CURIE'
    );
    is(
        $individuals->[0]{measures}[0]{assayCode}{id},
        'LOINC:5792-7',
        'FHIR Observation maps its assay coding'
    );
    is(
        $individuals->[0]{phenotypicFeatures}[0]{featureType}{id},
        'HP:0001250',
        'HPO-coded Observation maps to a phenotypic feature'
    );
    is(
        $individuals->[0]{info}{phenopacket}{biosamples}[0]{measurements}[0]{assay}{id},
        'LOINC:718-7',
        'Specimen-linked Observation remains attached to its PXF biosample'
    );
}

{
    my $before = JSON::XS->new->canonical->encode($fixture);
    my $convert = Convert::Pheno->new(
        {
            method => 'fhir2bff',
            data   => $fixture,
            test   => 1,
        }
    );

    my $first = $convert->fhir2bff;
    is(
        JSON::XS->new->canonical->encode($fixture),
        $before,
        'FHIR conversion does not mutate a caller-owned Bundle'
    );
    my $second = $convert->fhir2bff;
    is_deeply(
        [ map { $_->{id} } @{$second} ],
        [ map { $_->{id} } @{$first} ],
        'an in-memory FHIR converter can be reused'
    );
}

{
    my $individuals = Convert::Pheno->new(
        {
            method      => 'fhir2bff',
            data        => $fixture,
            source_info => 0,
            test        => 1,
        }
    )->fhir2bff;

    ok(
        !exists $individuals->[0]{info}{fhir},
        '--no-source-info omits raw FHIR resources'
    );
    ok(
        exists $individuals->[0]{info}{phenopacket}{biosamples},
        'semantic Phenopacket biosamples remain without raw FHIR provenance'
    );
}

{
    my $convert = Convert::Pheno->new(
        {
            method   => 'fhir2bff',
            in_files => [$fixture_file],
            entities => [qw(individuals biosamples datasets cohorts)],
            derived_entity_overrides => {
                datasets => { name => 'Configured FHIR study name' },
            },
            test => 1,
        }
    );
    my $bundle = $convert->_run_bundle_view;

    is(
        $bundle->entities('biosamples')->[0]{measurements}[0]{assayCode}{id},
        'LOINC:718-7',
        'FHIR Specimen emits a first-class BFF biosample with measurements'
    );
    is(
        $bundle->entities('datasets')->[0]{name},
        'Configured FHIR study name',
        'explicit entity metadata overrides FHIR ResearchStudy metadata'
    );
    is(
        $bundle->entities('cohorts')->[0]{cohortSize},
        1,
        'FHIR Group supplies the derived cohort size'
    );
}

{
    my ($patient) = map { $_->{resource} }
      grep { $_->{resource}{resourceType} eq 'Patient' } @{ $fixture->{entry} };
    my ($condition) = map { $_->{resource} }
      grep { $_->{resource}{resourceType} eq 'Condition' } @{ $fixture->{entry} };
    my ($procedure) = map { $_->{resource} }
      grep { $_->{resource}{resourceType} eq 'Procedure' } @{ $fixture->{entry} };

    my $bundle_a = {
        resourceType => 'Bundle',
        type         => 'collection',
        entry        => [
            { fullUrl => "urn:uuid:$patient_id", resource => dclone($patient) },
            { resource => dclone($condition) },
        ],
    };
    my $bundle_b = {
        resourceType => 'Bundle',
        type         => 'collection',
        entry        => [
            { fullUrl => "urn:uuid:$patient_id", resource => dclone($patient) },
            { resource => dclone($procedure) },
        ],
    };

    my $source = source_adapter(
        Convert::Pheno->new(
            {
                method => 'fhir2bff',
                data   => [ $bundle_a, $bundle_b ],
            }
        ),
        'fhir'
    )->load;

    is( scalar @{ $source->data }, 1, 'multiple Bundles merge a repeated Patient identity' );
    is(
        scalar @{ $source->data->[0]{resources} },
        2,
        'patient-scoped resources from multiple Bundles share one bucket'
    );
}

{
    my $bad = dclone($fixture);
    $bad->{type} = 'not-a-bundle-type';
    throws_ok(
        sub {
            source_adapter(
                Convert::Pheno->new( { method => 'fhir2bff', data => $bad } ),
                'fhir'
            )->load;
        },
        qr/invalid or missing type/,
        'FHIR source rejects an invalid Bundle type'
    );
}

{
    my $bad = dclone($fixture);
    $bad->{entry} = [
        grep { $_->{resource}{resourceType} ne 'Patient' } @{ $bad->{entry} }
    ];
    throws_ok(
        sub {
            source_adapter(
                Convert::Pheno->new( { method => 'fhir2bff', data => $bad } ),
                'fhir'
            )->load;
        },
        qr/must contain at least one Patient/,
        'FHIR source requires a Patient resource'
    );
}

done_testing();
