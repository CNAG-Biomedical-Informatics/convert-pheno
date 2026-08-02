#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);

use File::Temp qw(tempfile);
use JSON::XS;
use Test::Exception;
use Test::More;

use Convert::Pheno;
use Convert::Pheno::CDISC::ODM::Detector qw(detect_odm_document);
use Convert::Pheno::CDISC::ODM::Record;
use Convert::Pheno::CDISC::ODM::V2;
use Convert::Pheno::Context;
use Convert::Pheno::Operations qw(is_http_conversion);
use Convert::Pheno::Source qw(source_adapter);
use Convert::Pheno::Tabular::ToBFF qw(run_tabular_to_bundle);
use Test::ConvertPheno qw(cli_script_path load_json_file run_command_capture);

my $mapping_file = 't/cdiscodm2bff/in/generic_mapping.yaml';
my %fixture = (
    v1 => 't/cdiscodm2bff/in/generic_odm_v1.xml',
    v2 => 't/cdiscodm2bff/in/generic_odm_v2.xml',
);

{
    package Local::ODMMetadataCatalog;

    sub provider_for {
        return $_[0]->{provider};
    }
}

sub load_odm_source {
    my ( $file, %extra ) = @_;
    my $convert = Convert::Pheno->new(
        {
            method       => 'cdiscodm2bff',
            in_file      => $file,
            mapping_file => $mapping_file,
            schema_file  => 'share/schema/mapping-v2.json',
            %extra,
        }
    );
    return source_adapter( $convert, 'cdisc-odm' )->load;
}

my %expected = (
    v1 => {
        adapter    => 'v1',
        groups     => 3,
        id         => 'OC-001',
        odmVersion => '1.3.2',
        vendor     => 'openclinica',
    },
    v2 => {
        adapter    => 'v2',
        groups     => 4,
        id         => 'ODM2-001',
        odmVersion => '2.0.0',
        vendor     => 'standard',
    },
);

for my $version (qw(v1 v2)) {
    my $source = load_odm_source( $fixture{$version} );
    my $descriptor = $source->artifact('odm_descriptor');
    is( $descriptor->{adapter}, $expected{$version}{adapter}, "$version selects its strict ODM adapter" );
    is( $descriptor->{odmVersion}, $expected{$version}{odmVersion}, "$version retains its declared ODM version" );
    is( $descriptor->{vendor}, $expected{$version}{vendor}, "$version detects source-system provenance" );
    is(
        $source->artifact('entity_mapping')->{_compiled}{recordProfile},
        'cdisc-odm',
        "$version compiles the embedded-metadata mapping profile",
    );

    my $record = $source->data->[0];
    isa_ok( $record, 'Convert::Pheno::CDISC::ODM::Record', "$version normalized record" );
    is( $record->value('SEX'), 'Female', "$version decodes CodeList values from embedded metadata" );
    is( $record->value('SITE'), 'Barcelona', "$version collapses repeated identical scalar values" );
    throws_ok { $record->value('DIAG') }
      qr/Ambiguous CDISC-ODM scalar field <DIAG>.*itemGroup/si,
      "$version rejects differing repeated values in scalar context";

    my $diagnosis_views = $record->views_for('DIAG');
    is_deeply(
        [ map { $_->value('DIAG') } @{$diagnosis_views} ],
        [ 'Headache', 'Nasal congestion' ],
        "$version exposes one collection view per repeated item group",
    );
    is_deeply(
        [ map { $_->value('AGE') } @{$diagnosis_views} ],
        [ 30, 31 ],
        "$version resolves companion fields in the same occurrence",
    );

    my $snapshot = $record->columns_snapshot;
    is( $snapshot->{SITE}, 'Barcelona', "$version retains collapsible fields in the flat snapshot" );
    ok( !exists $snapshot->{DIAG}, "$version does not flatten ambiguous occurrence values" );
    ok( !grep( { /DIAG.*(?:repeat|group)/i } @{ $record->headers } ), "$version does not expose synthetic composite field names" );

    my $converter = bless {
        data_mapping_file => $source->artifact('entity_mapping'),
        source_info       => 1,
        test              => 1,
    }, 'Local::ODMConverter';
    my $context = Convert::Pheno::Context->new(
        {
            source_format => 'cdisc-odm',
            target_format => 'beacon',
            entities      => ['individuals'],
        }
    );
    my $bundle = run_tabular_to_bundle( $converter, $record, $context );
    my $individual = $bundle->primary_entity('individuals');

    is( $individual->{id}, $expected{$version}{id}, "$version maps the subject identifier" );
    is_deeply(
        [ map { $_->{diseaseCode}{label} } @{ $individual->{diseases} } ],
        [ 'Headache', 'Nasal Congestion' ],
        "$version fans repeated source groups into Beacon diseases",
    );
    is_deeply(
        [
            map { $_->{ageOfOnset}{age}{iso8601duration} }
              @{ $individual->{diseases} }
        ],
        [ 'P30Y', 'P31Y' ],
        "$version keeps each disease age in its source occurrence",
    );
    is(
        scalar @{ $individual->{info}{CDISC_ODM}{itemGroups} },
        $expected{$version}{groups},
        "$version emits occurrence-aware ODM provenance",
    );
    ok( !exists $individual->{info}{CSV_columns}, "$version is not reported as CSV provenance" );
    ok( !exists $individual->{info}{REDCap_columns}, "$version is not reported as REDCap provenance" );
}

throws_ok {
    load_odm_source(
        $fixture{v1},
        redcap_dictionary => 't/redcap2bff/in/redcap_dictionary.csv',
    );
}
qr/--redcap-dictionary is only valid for REDCap-origin CDISC-ODM/,
  'generic ODM rejects the REDCap-only dictionary option';

{
    my $convert = Convert::Pheno->new(
        {
            method       => 'cdiscodm2bff',
            in_file      => 't/cdiscodm2bff/in/cdisc_odm_data.xml',
            mapping_file => 't/redcap2bff/in/redcap_mapping.yaml',
            schema_file  => 'share/schema/mapping-v2.json',
        }
    );
    throws_ok { source_adapter( $convert, 'cdisc-odm' )->load }
      qr/REDCap-origin CDISC-ODM input requires --redcap-dictionary/,
      'REDCap-origin ODM still requires its external REDCap dictionary';
}

throws_ok {
    detect_odm_document(
        {
            ODM => {
                '-xmlns'      => 'http://www.cdisc.org/ns/odm/v1.3',
                '-ODMVersion' => '2.0.0',
                '-FileType'   => 'Snapshot',
            }
        }
    );
}
qr/namespace\/version mismatch/,
  'namespace and ODM version mismatches fail before parsing records';

throws_ok {
    detect_odm_document(
        {
            ODM => {
                '-xmlns'      => 'http://www.cdisc.org/ns/odm/v1.3',
                '-ODMVersion' => '1.3.2',
                '-FileType'   => 'Transactional',
            }
        }
    );
}
qr/only Snapshot input is supported/,
  'transactional ODM input is rejected explicitly';

throws_ok {
    Convert::Pheno::CDISC::ODM::Record->new(
        {
            context => { subjectId => 'P1' },
            groups  => [
                {
                    context   => { itemGroupOID => 'IG.ONE' },
                    scopePath => ['IG.ONE'],
                    items     => [
                        { itemOID => 'DUPLICATE', value => 'a' },
                        { itemOID => 'DUPLICATE', value => 'b' },
                    ],
                },
            ],
        }
    );
}
qr/Duplicate CDISC-ODM ItemOID <DUPLICATE>/,
  'duplicate ItemOID values in one full occurrence identity are rejected';

{
    my $metadata = bless { rows => {} },
      'Convert::Pheno::CDISC::ODM::Metadata::Provider';
    throws_ok {
        Convert::Pheno::CDISC::ODM::Record->new(
            {
                context => { subjectId => 'P1' },
                groups  => [
                    {
                        context   => { itemGroupOID => 'IG.ONE' },
                        scopePath => ['IG.ONE'],
                        items     => [ { itemOID => 'UNKNOWN', value => 'a' } ],
                    },
                ],
                metadata       => $metadata,
                record_profile => 'cdisc-odm',
            }
        );
    }
    qr/references no ItemDef in the active MetaDataVersion/,
      'generic ODM rejects clinical items missing from embedded metadata';
}

{
    my $metadata = bless {
        rows => {
            ITEM => {
                'Field Label' => 'Item',
                'Field Note'  => q{},
                'Field Type'  => 'text',
            },
        },
      }, 'Convert::Pheno::CDISC::ODM::Metadata::Provider';
    my $catalog = bless { provider => $metadata }, 'Local::ODMMetadataCatalog';
    my $descriptor = {
        adapter       => 'v2',
        namespaces    => {},
        odmVersion    => '2.0.0',
        recordProfile => 'cdisc-odm',
        root          => {
            ClinicalData => {
                '-StudyOID'          => 'S',
                '-MetaDataVersionOID' => 'M',
                SubjectData          => {
                    '-SubjectKey' => 'P1',
                    StudyEventData => {
                        '-StudyEventOID' => 'E1',
                        ItemGroupData    => {
                            '-ItemGroupOID' => 'G1',
                            ItemData       => {
                                '-ItemOID' => 'ITEM',
                                Value      => [ { '~' => 'a' }, { '~' => 'b' } ],
                            },
                        },
                    },
                },
            },
        },
    };
    throws_ok {
        Convert::Pheno::CDISC::ODM::V2->parse_records(
            $descriptor,
            metadata_catalog => $catalog,
        );
    }
    qr/contains multiple Value elements/,
      'ODM 2.0 rejects multi-valued item occurrences instead of losing data';
}

ok( !is_http_conversion('cdiscodm2bff'), 'CDISC-ODM remains outside the HTTP API contract' );

{
    my ( $fh, $outfile ) = tempfile( SUFFIX => '.json', UNLINK => 1 );
    close $fh;
    my ( $status, undef, $stderr ) = run_command_capture(
        command => [
            $^X,
            cli_script_path(),
            '-icdisc-odm', $fixture{v2},
            '--mapping-file', $mapping_file,
            '-obff', $outfile,
            '-O',
            '--test',
        ],
    );
    is( $status, 0, 'CLI accepts generic ODM without a REDCap dictionary' )
      or diag $stderr;
    is( load_json_file($outfile)->[0]{id}, 'ODM2-001', 'CLI writes the generic ODM conversion result' );
}

done_testing();
