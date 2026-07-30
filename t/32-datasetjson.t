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

my @files = sort glob 't/datasetjson2bff/in/*.json';
my @datasets = map { load_json_file($_) } @files;
my ($dm) = grep { $_->{name} eq 'DM' } @datasets;
my ($mh) = grep { $_->{name} eq 'MH' } @datasets;

{
    my $convert = Convert::Pheno->new(
        {
            method   => 'datasetjson2bff',
            in_files => \@files,
            test     => 1,
        }
    );
    my $source = source_adapter( $convert, 'dataset-json' )->load;

    is( scalar @{ $source->data }, 2, 'Dataset-JSON source groups rows into DM participants' );
    is_deeply(
        [ map { $_->{id} } @{ $source->data } ],
        [qw(P001 P002)],
        'Dataset-JSON source preserves DM participant order'
    );
    ok( $source->owned, 'normalized Dataset-JSON subjects are adapter-owned' );
    is(
        $source->artifact('dataset_metadata')->{studyOID},
        'STUDY-JSON-01',
        'Dataset-JSON source exposes study metadata'
    );
    ok(
        exists $source->artifact('subject_independent_domains')->{TS},
        'Dataset-JSON source separates subject-independent trial domains'
    );
}

{
    my $before = JSON::XS->new->canonical->encode(\@datasets);
    my $convert = Convert::Pheno->new(
        {
            method => 'datasetjson2bff',
            data   => \@datasets,
            test   => 1,
        }
    );
    my $individuals = $convert->datasetjson2bff;

    is( scalar @{$individuals}, 2, 'datasetjson2bff emits one individual per USUBJID' );
    is( $individuals->[0]{id}, 'P001', 'datasetjson2bff maps USUBJID to individual id' );
    is( $individuals->[0]{sex}{id}, 'NCIT:C20197', 'datasetjson2bff maps SDTM sex' );
    is(
        $individuals->[0]{measures}[0]{assayCode}{id},
        'CDISC:LBTESTCD.ALT',
        'datasetjson2bff preserves SDTM test identity as a source-derived CURIE'
    );
    is(
        $individuals->[0]{measures}[1]{measurementValue}{id},
        'CDISC:LBSTRESC.NEGATIVE',
        'datasetjson2bff maps categorical measurement results'
    );
    is_deeply(
        $individuals->[0]{info}{datasetJson}{unmappedDomains},
        ['QS'],
        'datasetjson2bff identifies retained domains without first-class mappings'
    );
    is(
        $individuals->[1]{info}{phenopacket}{vitalStatus}{status},
        'DECEASED',
        'datasetjson2bff maps the SDTM death flag to Phenopacket provenance'
    );
    is(
        JSON::XS->new->canonical->encode(\@datasets),
        $before,
        'Dataset-JSON conversion does not mutate caller-owned documents'
    );

    my $second_pass = $convert->datasetjson2bff;
    is_deeply(
        [ map { $_->{id} } @{$second_pass} ],
        [qw(P001 P002)],
        'an in-memory Dataset-JSON converter can be reused after releasing normalized data'
    );
}

{
    my $convert = Convert::Pheno->new(
        {
            method      => 'datasetjson2bff',
            data        => \@datasets,
            source_info => 0,
            test        => 1,
        }
    );
    my $individuals = $convert->datasetjson2bff;

    ok(
        !exists $individuals->[0]{info}{datasetJson},
        '--no-source-info semantics omit raw Dataset-JSON rows'
    );
    ok(
        exists $individuals->[0]{info}{phenopacket}{dateOfBirth},
        'semantic Phenopacket metadata remains available without raw source provenance'
    );
}

{
    my $convert = Convert::Pheno->new(
        {
            method   => 'datasetjson2bff',
            in_files => \@files,
            entities => [qw(datasets cohorts)],
            derived_entity_overrides => {
                datasets => { name => 'Configured study name' },
            },
            test => 1,
        }
    );
    my $bundle = $convert->_run_bundle_view;

    is(
        $bundle->entities('datasets')->[0]{id},
        'STUDY-JSON-01',
        'Dataset-JSON studyOID prepopulates the derived dataset id'
    );
    is(
        $bundle->entities('datasets')->[0]{name},
        'Configured study name',
        'explicit entity metadata overrides source-derived Dataset-JSON metadata'
    );
    is(
        $bundle->entities('cohorts')->[0]{cohortSize},
        2,
        'Dataset-JSON derived cohort contains every DM participant'
    );
}

{
    my $dm_with_death_date = dclone($dm);
    push @{ $dm_with_death_date->{columns} },
      {
        itemOID => 'IT.DM.DTHDTC',
        name     => 'DTHDTC',
        label    => 'Date/Time of Death',
        dataType => 'string',
      };
    push @{ $dm_with_death_date->{rows}[0] }, q{};
    push @{ $dm_with_death_date->{rows}[1] }, '2025-03-04';

    my $individuals = Convert::Pheno->new(
        {
            method => 'datasetjson2bff',
            data   => [$dm_with_death_date],
            test   => 1,
        }
    )->datasetjson2bff;

    is(
        $individuals->[1]{info}{phenopacket}{vitalStatus}{timeOfDeath}{timestamp},
        '2025-03-04T00:00:00Z',
        'Dataset-JSON maps DTHDTC to Phenopackets vitalStatus timeOfDeath provenance'
    );
}

{
    my $bad = dclone($dm);
    pop @{ $bad->{rows}[0] };
    throws_ok(
        sub {
            source_adapter(
                Convert::Pheno->new( { method => 'datasetjson2bff', data => [$bad] } ),
                'dataset-json'
            )->load;
        },
        qr/row 1 has .* values but .* columns are defined/,
        'Dataset-JSON rejects rows whose width differs from columns metadata'
    );
}

{
    my $bad = dclone($dm);
    $bad->{records}++;
    throws_ok(
        sub {
            source_adapter(
                Convert::Pheno->new( { method => 'datasetjson2bff', data => [$bad] } ),
                'dataset-json'
            )->load;
        },
        qr/declares .* records but contains .* rows/,
        'Dataset-JSON rejects incorrect record counts'
    );
}

{
    throws_ok(
        sub {
            source_adapter(
                Convert::Pheno->new( { method => 'datasetjson2bff', data => [ dclone($mh) ] } ),
                'dataset-json'
            )->load;
        },
        qr/requires exactly one <DM> dataset/,
        'Dataset-JSON SDTM input requires DM'
    );
}

{
    my $bad_mh = dclone($mh);
    $bad_mh->{rows}[0][0] = 'UNKNOWN';
    throws_ok(
        sub {
            source_adapter(
                Convert::Pheno->new(
                    {
                        method => 'datasetjson2bff',
                        data   => [ dclone($dm), $bad_mh ],
                    }
                ),
                'dataset-json'
            )->load;
        },
        qr/references unknown USUBJID <UNKNOWN>/,
        'Dataset-JSON rejects subject rows without a matching DM participant'
    );
}

done_testing();
