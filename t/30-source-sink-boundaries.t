#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use File::Spec;
use File::Temp qw(tempdir);
use JSON::XS;
use Path::Tiny qw(path);
use Test::Exception;
use Test::More;

use Convert::Pheno;
use Convert::Pheno::Emit::OMOP qw(
  omop_stream_targets_finalize
  omop_stream_targets_open
  omop_stream_targets_write
);
use Convert::Pheno::IO::FileIO qw(io_yaml_or_json);
use Convert::Pheno::Model::Bundle;
use Convert::Pheno::Sink::FileSet qw(
  resolve_entity_output_file
  resolve_omop_table_output_file
);
use Convert::Pheno::Source qw(source_adapter);

{
    my $data = {
        CONCEPT => [ { concept_id => 0, concept_name => 'No matching concept' } ],
        PERSON  => [ { person_id => 7, gender_concept_id => 0 } ],
    };
    my $before = JSON::XS->new->canonical->encode($data);
    my $convert = Convert::Pheno->new(
        {
            method => 'omop2bff',
            data   => $data,
        }
    );
    my $source = source_adapter( $convert, 'omop' )->load;

    isnt( $source->data, $data, 'OMOP memory source creates an owned table buffer' );
    ok( $source->owned, 'OMOP memory source marks its table buffer as adapter-owned' );
    $source->data->{PERSON}[0]{person_id} = 8;
    is( $data->{PERSON}[0]{person_id}, 7, 'OMOP memory source clones nested row data' );
    is(
        JSON::XS->new->canonical->encode($data),
        $before,
        'OMOP source preparation does not modify caller-owned tables'
    );
}

{
    my $data = { subject => { id => 'caller-1' } };
    my $convert = Convert::Pheno->new(
        {
            method => 'pxf2bff',
            data   => $data,
        }
    );
    my $source = source_adapter( $convert, 'pxf' )->load;

    is( $source->data, $data, 'structured memory source preserves the caller reference' );
    ok( !$source->owned, 'structured memory source remains caller-owned' );
}

{
    my $convert = Convert::Pheno->new(
        {
            method      => 'bff2pxf',
            in_file     => 't/bff2pxf/in/individuals.json',
            in_textfile => 1,
        }
    );
    my $source = source_adapter( $convert, 'beacon' )->load;

    is( ref( $source->data ), 'ARRAY', 'structured file source parses JSON input' );
    ok( $source->owned, 'structured file source marks its parsed data as owned' );
}

{
    my $convert = Convert::Pheno->new(
        {
            method       => 'csv2bff',
            in_file      => 't/csv2bff/in/csv_data.csv',
            mapping_file => 't/csv2bff/in/csv_mapping.yaml',
            schema_file  => 'share/schema/mapping-v2.json',
            sep          => ',',
        }
    );
    my $source = source_adapter( $convert, 'csv' )->load;

    ok( @{ $source->data }, 'tabular source parses CSV rows' );
    is(
        ref( $source->artifact('entity_mapping') ),
        'HASH',
        'tabular source returns the selected mapping artifact'
    );
}

{
    my $convert = Convert::Pheno->new(
        {
            method             => 'cdiscodm2bff',
            in_file            => 't/cdiscodm2bff/in/cdisc_odm_data.xml',
            mapping_file       => 't/redcap2bff/in/redcap_mapping.yaml',
            redcap_dictionary  => 't/redcap2bff/in/redcap_dictionary.csv',
            schema_file        => 'share/schema/mapping-v2.json',
        }
    );
    my $source = source_adapter( $convert, 'cdisc-odm' )->load;

    isa_ok(
        $source->data->[0],
        'Convert::Pheno::CDISC::ODM::Record',
        'CDISC-ODM source adapter emits occurrence-aware records',
    );
    isa_ok(
        $source->artifact('redcap_dictionary'),
        'Convert::Pheno::Tabular::REDCap::Dictionary',
        'CDISC-ODM source adapter exposes dictionary metadata'
    );
}

{
    my $convert = Convert::Pheno->new(
        {
            method  => 'openehr2bff',
            in_file => 't/openehr2bff/in/gecco_personendaten_patient.json',
        }
    );
    my $source = source_adapter( $convert, 'openehr' )->load;

    is( ref( $source->data ), 'ARRAY', 'openEHR source adapter returns document sets' );
    ok(
        exists $source->data->[0]{compositions},
        'openEHR source adapter normalizes documents to composition envelopes'
    );
}

{
    my $data = {
        compositions => [ { uid => { value => 'composition-1' } } ],
    };
    my $convert = Convert::Pheno->new(
        {
            method => 'openehr2bff',
            data   => $data,
        }
    );
    my $source = source_adapter( $convert, 'openehr' )->load;

    isnt( $source->data, $data, 'openEHR normalization uses a separate top-level buffer' );
    is( $source->data->[0], $data, 'openEHR normalization preserves caller document references' );
    ok( $source->owned, 'openEHR marks its normalized buffer as adapter-owned' );
}

{
    my @files = sort glob 't/datasetjson2bff/in/*.json';
    my $convert = Convert::Pheno->new(
        {
            method   => 'datasetjson2bff',
            in_files => \@files,
        }
    );
    my $source = source_adapter( $convert, 'dataset-json' )->load;

    is( scalar @{ $source->data }, 2, 'Dataset-JSON source adapter groups SDTM rows by USUBJID' );
    ok(
        exists $source->data->[0]{domains}{LB},
        'Dataset-JSON source adapter retains subject domain rows'
    );
}

{
    my $error;
    eval { source_adapter( bless( {}, 'Convert::Pheno' ), 'unsupported-format' ); 1 }
      or $error = $@;
    like(
        $error,
        qr/No source adapter is registered for <unsupported-format>/,
        'unknown source formats fail at the adapter boundary'
    );
}

{
    my $tmpdir = tempdir( CLEANUP => 1 );
    my $outfile = File::Spec->catfile( $tmpdir, 'streamed-individuals.jsonl' );
    my $convert = bless {
        entities => ['individuals'],
        out_dir  => $tmpdir,
        out_file => $outfile,
    }, 'Convert::Pheno';

    ok( omop_stream_targets_write( $convert, undef ), 'stream sink accepts an empty participant result' );
    ok( omop_stream_targets_write( $convert, { id => 'person-1' } ), 'stream sink writes an individual' );
    ok( omop_stream_targets_write( $convert, { id => 'person-1' } ), 'stream sink accepts a duplicate individual' );
    ok( omop_stream_targets_write( $convert, { id => 'person-2' } ), 'stream sink writes the next individual' );
    ok( omop_stream_targets_finalize($convert), 'stream sink commits scalar participant output' );

    my @rows = map { JSON::XS->new->decode($_) }
      grep { length }
      split /\n/, path($outfile)->slurp_utf8;
    is_deeply(
        [ map { $_->{id} } @rows ],
        [qw(person-1 person-2)],
        'stream sink suppresses duplicate participant rows',
    );
    ok( omop_stream_targets_finalize($convert), 'finalizing an inactive stream is harmless' );
}

{
    my $tmpdir = tempdir( CLEANUP => 1 );
    my $biosamples_file = File::Spec->catfile( $tmpdir, 'samples.jsonl' );
    my $convert = bless {
        entities => [qw(individuals biosamples)],
        out_dir  => $tmpdir,
        output_name_overrides => { biosamples => $biosamples_file },
    }, 'Convert::Pheno';
    my $bundle = Convert::Pheno::Model::Bundle->new(
        { entities => [qw(individuals biosamples)] }
    );
    $bundle->add_entity( individuals => { id => 'person-1' } );
    $bundle->add_entity( biosamples  => { id => 'sample-1' } );

    ok( omop_stream_targets_write( $convert, $bundle ), 'stream sink writes entity-aware bundles' );
    ok( omop_stream_targets_finalize( $convert, 0 ), 'stream sink can discard an incomplete entity bundle' );
    ok( !-e File::Spec->catfile( $tmpdir, 'individuals.json' ), 'discarded stream does not publish individuals' );
    ok( !-e $biosamples_file, 'discarded stream does not publish an overridden biosample file' );
}

{
    my $tmpdir = tempdir( CLEANUP => 1 );
    my $convert = bless {
        entities => [qw(individuals biosamples)],
        out_dir  => $tmpdir,
        output_name_overrides => {
            biosamples => File::Spec->catfile( $tmpdir, 'missing', 'biosamples.json' ),
        },
    }, 'Convert::Pheno';

    throws_ok(
        sub { omop_stream_targets_open($convert) },
        qr/(?:No such file|Error in tempfile)/,
        'opening multiple stream targets rolls back when a later path is invalid',
    );
    opendir( my $dir, $tmpdir );
    my @staged = grep { /^\.convert-pheno-/ } readdir $dir;
    closedir($dir);
    is_deeply( \@staged, [], 'failed stream setup removes earlier staged files' );
}

{
    my $tmpdir = tempdir( CLEANUP => 1 );
    my $individuals_file = File::Spec->catfile( $tmpdir, 'individuals.json' );
    my $sink = Convert::Pheno::Sink::FileSet->new(
        {
            request => {
                method   => 'bff2pxf',
                out_dir  => $tmpdir,
                entities => ['individuals'],
            },
            out_file => $individuals_file,
        }
    );
    $sink->write_result( data => [ { id => 'out-1' } ] );

    is_deeply(
        io_yaml_or_json( { filepath => $individuals_file, mode => 'read' } ),
        [ { id => 'out-1' } ],
        'file-set sink serializes structured output atomically'
    );

    my $bundle = Convert::Pheno::Model::Bundle->new(
        { entities => [ 'individuals', 'biosamples' ] }
    );
    $bundle->add_entity( individuals => { id => 'person-1' } );
    $bundle->add_entity( biosamples  => { id => 'sample-1' } );
    my $bundle_sink = Convert::Pheno::Sink::FileSet->new(
        {
            request => {
                method   => 'pxf2bff',
                out_dir  => $tmpdir,
                entities => [ 'individuals', 'biosamples' ],
            },
        }
    );
    $bundle_sink->write_result( bundle => $bundle );
    ok( -f File::Spec->catfile( $tmpdir, 'biosamples.json' ), 'file-set sink writes each requested bundle entity' );

    is(
        resolve_entity_output_file(
            {
                out_dir => $tmpdir,
                output_name_overrides => { individuals => 'custom.json' },
            },
            'individuals',
        ),
        'custom.json',
        'entity sink resolver honors output-name overrides'
    );
    is(
        resolve_omop_table_output_file( { out_dir => $tmpdir }, 'PERSON' ),
        File::Spec->catfile( $tmpdir, 'PERSON.csv' ),
        'OMOP sink resolver uses stable table filenames'
    );

    my $flat_file = File::Spec->catfile( $tmpdir, 'flat.csv' );
    my $flat_sink = Convert::Pheno::Sink::FileSet->new(
        {
            request  => { method => 'bff2csv', sep => ',' },
            out_file => $flat_file,
        }
    );
    $flat_sink->write_result( data => [ { id => 'row-1' } ] );
    ok( -s $flat_file, 'file-set sink writes flattened CSV output' );

    my ( @before_write, @on_write );
    my $person_file = File::Spec->catfile( $tmpdir, 'PERSON.csv' );
    my $omop_sink = Convert::Pheno::Sink::FileSet->new(
        {
            request => {
                method  => 'bff2omop',
                out_dir => $tmpdir,
            },
            before_write => sub { push @before_write, $_[0]; return 1 },
            on_write     => sub { push @on_write,     $_[0]; return 1 },
        }
    );
    $omop_sink->write_result( data => { PERSON => [ { person_id => 7 } ] } );
    ok( -s $person_file, 'file-set sink writes OMOP table output' );
    is_deeply( \@before_write, [$person_file], 'OMOP sink checks each table target' );
    is_deeply( \@on_write, [$person_file], 'OMOP sink reports each table write' );
}

done_testing();
