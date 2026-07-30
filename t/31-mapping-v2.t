#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use File::Temp qw(tempfile);
use JSON::PP ();
use Storable qw(dclone);
use Test::Exception;
use Test::More;

use Convert::Pheno::Context;
use Convert::Pheno::IO::CSVHandler qw(read_mapping_file);
use Convert::Pheno::Mapping::Compiler qw(compile_mapping);
use Convert::Pheno::Tabular::ToBFF qw(run_tabular_to_bundle);
use Test::ConvertPheno qw(write_json_file);

my $mapping = {
    mappingVersion => 2,
    source         => { profile => 'csv' },
    target         => {
        model         => 'beacon',
        schemaVersion => '2.0.0',
    },
    project => {
        id      => 'mapping_v2_test',
        version => '1',
    },
    defaults => { ontology => 'ncit' },
    records  => {
        baseline => {
            strategy     => 'firstNonNull',
            sourceFields => ['Sex'],
        },
    },
    beacon => {
        individuals => {
            id => {
                sourceFields => [qw(ParticipantId Visit)],
                primaryKey   => 'ParticipantId',
            },
            sex => {
                sourceField => 'Sex',
                query       => { from => 'value' },
                terms       => {
                    Female => {
                        id    => 'NCIT:C16576',
                        label => 'Female',
                    },
                },
            },
            interventionsOrProcedures => {
                defaults => {
                    bodySite => { query => 'Intestine' },
                },
                rules => [
                    {
                        sourceField  => 'Procedure',
                        optional     => JSON::PP::true,
                        procedureCode => { query => 'Procedure' },
                        bodySite     => undef,
                    },
                ],
            },
        },
        biosamples => {
            defaults => {
                id           => { from => 'sourceValue' },
                individualId => { from => 'individualId' },
                biosampleStatus => {
                    term => {
                        id    => 'NCIT:C126101',
                        label => 'Not Available',
                    },
                },
                sampleOriginType => {
                    term => {
                        id    => 'NCIT:C17610',
                        label => 'Blood Sample',
                    },
                },
            },
            rules => [
                {
                    sourceField    => 'SampleId',
                    when          => { nonEmpty => JSON::PP::true },
                    collectionDate => { sourceField => 'SampleDate' },
                    notes          => { sourceField => 'SampleNote' },
                    obtentionProcedure => {
                        procedureCode => {
                            term => {
                                id    => 'NCIT:C15189',
                                label => 'Biopsy',
                            },
                        },
                    },
                    measurements => {
                        defaults => {
                            measurementValue => {
                                quantity => {
                                    unit => {
                                        term => {
                                            id    => 'UO:0000021',
                                            label => 'gram',
                                        },
                                    },
                                    referenceRange => {
                                        low  => 0,
                                        high => 10,
                                    },
                                },
                            },
                            procedure => {
                                procedureCode => {
                                    term => {
                                        id    => 'NCIT:C68785',
                                        label => 'Weighing',
                                    },
                                },
                            },
                        },
                        rules => [
                            {
                                sourceField => 'SampleMass',
                                when        => { nonEmpty => JSON::PP::true },
                                assayCode   => {
                                    term => {
                                        id    => 'NCIT:C25208',
                                        label => 'Weight',
                                    },
                                },
                                measurementValue => {
                                    quantity => {
                                        value => { from => 'sourceValue' },
                                    },
                                },
                            },
                        ],
                    },
                    info => { sourceFields => ['SampleSource'] },
                },
            ],
        },
    },
};

my ( $mapping_fh, $mapping_file ) = tempfile( SUFFIX => '.json', UNLINK => 1 );
close $mapping_fh;
write_json_file( $mapping_file, $mapping );

my $validated_mapping;
lives_ok {
    $validated_mapping = read_mapping_file(
        {
            mapping_file         => $mapping_file,
            schema_file          => 'share/schema/mapping.json',
            self_validate_schema => 0,
        }
    );
}
'the focused biosample mapping follows the mapping v2 schema';

my @headers = qw(
  ParticipantId Visit Sex SampleId SampleDate SampleNote SampleMass SampleSource
);
my $mapping_before_compile = dclone($validated_mapping);
my $compiled = compile_mapping(
    $validated_mapping,
    source_profile => 'csv',
    headers        => \@headers,
);
is_deeply(
    $validated_mapping,
    $mapping_before_compile,
    'compilation does not mutate the author-facing mapping',
);
is(
    $compiled->{beacon}{biosamples}{mappings}[0]{source}{field},
    'SampleId',
    'compact sourceField is compiled to the execution selector',
);
is(
    $compiled->{beacon}{biosamples}{mappings}[0]{target}{measurements}[0]
      {target}{measurementValue}{quantity}{unit}{term}{id},
    'UO:0000021',
    'nested collection defaults are deep-merged into compiled rules',
);
ok(
    !exists $compiled->{beacon}{individuals}{interventionsOrProcedures}[0]
      {target}{bodySite},
    'null removes an optional inherited target property',
);

my $converter = bless {
    data_mapping_file => $compiled,
    source_info       => 1,
    test              => 1,
}, 'Local::TabularConverter';
my $context = Convert::Pheno::Context->new(
    {
        source_format => 'csv',
        target_format => 'beacon',
        entities      => [qw(individuals biosamples)],
    }
);

my $baseline_row = {
    ParticipantId => 'P1',
    Visit         => 'baseline',
    Sex           => 'Female',
    SampleId      => undef,
    SampleDate    => undef,
    SampleNote    => undef,
    SampleMass    => undef,
    SampleSource  => undef,
};
my $followup_row = {
    ParticipantId => 'P1',
    Visit         => 'follow-up',
    Sex           => undef,
    SampleId      => 'BIO-1',
    SampleDate    => '2025-04-15',
    SampleNote    => 'Aliquot A',
    SampleMass    => '4.5',
    SampleSource  => 'laboratory export',
};
my $baseline_before = dclone($baseline_row);
my $followup_before = dclone($followup_row);

my $baseline_bundle = run_tabular_to_bundle( $converter, $baseline_row, $context );
my $followup_bundle = run_tabular_to_bundle( $converter, $followup_row, $context );

is_deeply( $baseline_row, $baseline_before, 'baseline processing does not mutate the caller-owned row' );
is_deeply( $followup_row, $followup_before, 'follow-up processing does not mutate the caller-owned row' );
is( scalar @{ $baseline_bundle->entities('biosamples') }, 0, 'a row without a sample id emits no biosample' );

my $individual = $followup_bundle->primary_entity('individuals');
is( $individual->{id}, 'P1:follow-up', 'the follow-up row remains convertible after baseline propagation' );
is( $individual->{sex}{id}, 'NCIT:C16576', 'the propagated value is available to the target mapping' );
ok( !defined $individual->{info}{CSV_columns}{Sex}, 'individual provenance retains the original missing value' );

my $biosample = $followup_bundle->primary_entity('biosamples');
is( $biosample->{id}, 'BIO-1', 'mapping emits a first-class biosample id' );
is( $biosample->{individualId}, 'P1:follow-up', 'biosample references the generated individual' );
is( $biosample->{biosampleStatus}{id}, 'NCIT:C126101', 'biosample status is mapped as an ontology term' );
is( $biosample->{sampleOriginType}{id}, 'NCIT:C17610', 'sample origin is mapped as an ontology term' );
is( $biosample->{collectionDate}, '2025-04-15', 'collection date is normalized for BFF' );
is( $biosample->{notes}, 'Aliquot A', 'biosample notes are mapped from their explicit source field' );
is( $biosample->{obtentionProcedure}{procedureCode}{id}, 'NCIT:C15189', 'obtention procedure is mapping-driven' );
is( $biosample->{measurements}[0]{assayCode}{id}, 'NCIT:C25208', 'biosample measurement has an assay code' );
is( $biosample->{measurements}[0]{measurementValue}{quantity}{value}, 4.5, 'biosample measurement is numeric' );
is( $biosample->{measurements}[0]{measurementValue}{quantity}{unit}{id}, 'UO:0000021', 'biosample measurement has a CURIE unit' );
is( $biosample->{info}{SampleSource}, 'laboratory export', 'selected biosample source metadata is retained' );
ok( !defined $biosample->{info}{CSV_columns}{Sex}, 'biosample provenance also retains the original missing value' );

done_testing();
