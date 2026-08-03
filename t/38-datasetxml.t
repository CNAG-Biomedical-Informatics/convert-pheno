#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Path::Tiny qw(path);
use Storable qw(dclone);
use Test::Exception;
use Test::More;

use Convert::Pheno;
use Convert::Pheno::Source qw(source_adapter);
use Test::ConvertPheno qw(slurp_file temp_output_file test_ohdsi_db_dir);

my $fixture_dir = 't/datasetxml2bff/in';
my $define_file = "$fixture_dir/define.xml";
my @dataset_files = map { "$fixture_dir/$_.xml" } qw(dm mh lb ts);

sub build_datasetxml_converter {
    my (%extra) = @_;
    return Convert::Pheno->new(
        {
            method     => 'datasetxml2bff',
            define_xml => $define_file,
            in_files   => \@dataset_files,
            test       => 1,
            %extra,
        }
    );
}

{
    my $source = source_adapter(
        build_datasetxml_converter(),
        'dataset-xml',
    )->load;

    is( scalar @{ $source->data }, 2, 'Dataset-XML source groups DM participants' );
    is_deeply(
        [ map { $_->{id} } @{ $source->data } ],
        [qw(P001 P002)],
        'Dataset-XML source preserves DM row order'
    );
    is(
        $source->data->[0]{domains}{MH}[0]{MHSEQ},
        1,
        'Define-XML integer metadata controls value coercion'
    );
    ok(
        !defined $source->data->[0]{domains}{DM}[0]{DTHFL},
        'omitted ItemData is normalized as a missing value'
    );
    is(
        $source->artifact('dataset_metadata')->{defineXMLVersion},
        '2.0.0',
        'Dataset-XML source exposes its Define-XML version'
    );
    is(
        $source->artifact('subject_independent_domains')->{TS}[0]{TSVAL},
        'Dataset-XML example study',
        'ReferenceData without USUBJID remains study-level metadata'
    );
    ok( $source->owned, 'normalized Dataset-XML subjects are adapter-owned' );
}

{
    my $define_xml = path($define_file)->slurp_utf8;
    $define_xml =~ s{http://www\.cdisc\.org/ns/def/v2\.0}{http://www.cdisc.org/ns/def/v2.1}g;
    $define_xml =~ s{def:DefineVersion="2\.0\.0"}{def:DefineVersion="2.1.0"};

    my $source = source_adapter(
        Convert::Pheno->new(
            {
                method => 'datasetxml2bff',
                data   => {
                    define => $define_xml,
                    datasets => [ map { path($_)->slurp_utf8 } @dataset_files ],
                },
                test => 1,
            }
        ),
        'dataset-xml',
    )->load;

    is(
        $source->artifact('dataset_metadata')->{defineXMLVersion},
        '2.1.0',
        'Dataset-XML accepts Define-XML 2.1 metadata'
    );
}

{
    my $individuals = build_datasetxml_converter()->datasetxml2bff;
    is( scalar @{$individuals}, 2, 'datasetxml2bff emits one individual per DM row' );
    is(
        $individuals->[0]{diseases}[0]{diseaseCode}{id},
        'CDISC:MHDECOD.DIABETES_MELLITUS',
        'Dataset-XML reuses the SDTM disease mapping'
    );
    is(
        $individuals->[0]{measures}[0]{measurementValue}{quantity}{value},
        42,
        'Dataset-XML reuses the SDTM numeric measurement mapping'
    );
    is(
        $individuals->[0]{info}{datasetXml}{metaDataVersionOID},
        'MDV.STUDY-XML-01',
        'individual provenance records the resolved Define-XML metadata version'
    );
    ok(
        !exists $individuals->[0]{info}{datasetJson},
        'Dataset-XML provenance is not mislabeled as Dataset-JSON'
    );
}

{
    my $audit_file = temp_output_file( suffix => '.tsv' );
    my $individuals = Convert::Pheno->new(
        {
            method          => 'datasetxml2bff',
            define_xml      => "$fixture_dir/terminology/define.xml",
            in_files        => ["$fixture_dir/terminology/dm.xml"],
            term_audit_file => $audit_file,
            test            => 1,
        }
    )->datasetxml2bff;

    is_deeply(
        $individuals->[0]{ethnicity},
        {
            id    => 'NCIT:C41222',
            label => 'Not Hispanic or Latino',
        },
        'Dataset-XML resolves an explicit Define-XML NCI identifier and canonical label'
    );
    is_deeply(
        $individuals->[1]{ethnicity},
        {
            id    => 'CDISC:ETHNIC.UNKNOWN',
            label => 'Unknown',
        },
        'Dataset-XML retains a source-derived term when Define-XML has no supported NCI identifier'
    );

    my $audit = slurp_file($audit_file);
    like(
        $audit,
        qr/\tDM\.ETHNIC\tNOT HISPANIC OR LATINO\tNot Hispanic or Latino\tC41222\tid\tNot Hispanic or Latino\tNCIT:C41222\tncit\t[^\n]*\tmatched\texact_match\tkeep\tdefine_xml\texact\tnone\t[^\n]*(?:\n|\z)/,
        'terminology audit attributes an authoritative identifier to Define-XML'
    );
    like(
        $audit,
        qr/\tDM\.ETHNIC\tUNKNOWN\tUnknown\t\t\tUnknown\tCDISC:ETHNIC\.UNKNOWN\tcdisc\t[^\n]*\tnot_searched\tnot_searched\treview_source_fallback\tsource_fallback\tfallback_source\tsource_term\t[^\n]*(?:\n|\z)/,
        'terminology audit distinguishes a source-derived fallback'
    );
}

{
    my $bundle = build_datasetxml_converter(
        entities => [qw(individuals datasets cohorts)],
    )->_run_bundle_view;
    is(
        $bundle->entities('datasets')->[0]{name},
        'Dataset-XML example study',
        'TS title prepopulates Dataset-XML dataset metadata'
    );
    is(
        $bundle->entities('cohorts')->[0]{cohortSize},
        2,
        'Dataset-XML derived cohort includes every DM participant'
    );
}

{
    my $individuals = build_datasetxml_converter( source_info => 0 )->datasetxml2bff;
    ok(
        !exists $individuals->[0]{info}{datasetXml},
        '--no-source-info omits raw Dataset-XML rows'
    );
    ok(
        exists $individuals->[0]{info}{phenopacket}{dateOfBirth},
        'semantic Phenopacket metadata remains without raw XML provenance'
    );
}

{
    my $input = {
        define   => path($define_file)->slurp_utf8,
        datasets => [ map { path($_)->slurp_utf8 } @dataset_files ],
    };
    my $before = dclone($input);
    my $convert = Convert::Pheno->new(
        {
            method => 'datasetxml2bff',
            data   => $input,
            test   => 1,
        }
    );
    my $first  = $convert->datasetxml2bff;
    my $second = $convert->datasetxml2bff;

    is_deeply( $input, $before, 'Dataset-XML conversion does not mutate caller input' );
    is_deeply(
        [ map { $_->{id} } @{$second} ],
        [ map { $_->{id} } @{$first} ],
        'an in-memory Dataset-XML converter can be reused'
    );
}

{
    my $pxf = Convert::Pheno->new(
        {
            method     => 'datasetxml2pxf',
            define_xml => $define_file,
            in_files   => \@dataset_files,
            test       => 1,
        }
    )->datasetxml2pxf;
    is_deeply(
        [ map { $_->{subject}{id} } @{$pxf} ],
        [qw(P001 P002)],
        'datasetxml2pxf runs through the shared BFF pipeline'
    );
}

{
    my $tables = Convert::Pheno->new(
        {
            method           => 'datasetxml2omop',
            define_xml       => $define_file,
            in_files         => \@dataset_files,
            ohdsi_db         => 1,
            path_to_ohdsi_db => test_ohdsi_db_dir(),
            test             => 1,
        }
    )->datasetxml2omop;
    is( scalar @{ $tables->{PERSON} }, 2, 'datasetxml2omop emits PERSON rows' );
    is(
        scalar @{ $tables->{CONDITION_OCCURRENCE} },
        2,
        'datasetxml2omop emits condition rows'
    );
    is(
        scalar @{ $tables->{MEASUREMENT} },
        3,
        'datasetxml2omop emits measurement rows'
    );
}

{
    my $bad_dm = path( $dataset_files[0] )->slurp_utf8;
    $bad_dm =~ s/MDV\.STUDY-XML-01/MDV.MISSING/;
    my $input = {
        define   => path($define_file)->slurp_utf8,
        datasets => [
            $bad_dm,
            map { path($_)->slurp_utf8 } @dataset_files[ 1 .. $#dataset_files ],
        ],
    };

    throws_ok(
        sub {
            Convert::Pheno->new(
                {
                    method => 'datasetxml2bff',
                    data   => $input,
                    test   => 1,
                }
            )->datasetxml2bff;
        },
        qr/references missing Define-XML metadata/,
        'Dataset-XML rejects metadata references absent from Define-XML'
    );
}

{
    my $bad_dm = path( $dataset_files[0] )->slurp_utf8;
    $bad_dm =~ s/DEFINE\.STUDY-XML-01/DEFINE.MISSING/;
    my $input = {
        define   => path($define_file)->slurp_utf8,
        datasets => [
            $bad_dm,
            map { path($_)->slurp_utf8 } @dataset_files[ 1 .. $#dataset_files ],
        ],
    };

    throws_ok(
        sub {
            Convert::Pheno->new(
                {
                    method => 'datasetxml2bff',
                    data   => $input,
                    test   => 1,
                }
            )->datasetxml2bff;
        },
        qr/links to Define-XML <DEFINE\.MISSING>/,
        'Dataset-XML validates an optional PriorFileOID against Define-XML'
    );
}

done_testing();
