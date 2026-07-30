#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use File::Temp qw(tempdir);
use Test::More;
use Test::ConvertPheno qw(build_convert);
use Convert::Pheno::IO::FileIO qw(io_yaml_or_json);

my $tmpdir = tempdir( CLEANUP => 1 );
my $csv_file = "$tmpdir/raw-values.csv";
my $mapping_file = "$tmpdir/raw-values.yaml";

open my $fh, '>', $csv_file or die $!;
print {$fh} "PatientId,EventName,Sex,Ethnicity,Disease_1\n";
print {$fh} "00123,baseline,Male,,Diabetes\n";
close $fh;

io_yaml_or_json(
    {
        filepath => $mapping_file,
        mode     => 'write',
        data     => {
            mappingVersion => 2,
            source => {
                profiles => ['csv'],
            },
            target => {
                model         => 'beacon',
                schemaVersion => '2.0.0',
            },
            project => {
                id      => 'raw_values_test',
                version => 'test-0.1',
            },
            defaults => {
                ontology => 'ncit',
            },
            records => {},
            beacon => {
                individuals => {
                    id => {
                        source => {
                            fields     => [ 'PatientId', 'EventName' ],
                            primaryKey => 'PatientId',
                        },
                    },
                    sex => {
                        source => { field => 'Sex' },
                        target => { query => { from => 'value' } },
                    },
                    ethnicity => {
                        source => { field => 'Ethnicity' },
                        target => { query => { from => 'value' } },
                    },
                    diseases => [
                        {
                            source => { field => 'Disease_1' },
                            target => {
                                diseaseCode => {
                                    query => {
                                        from    => 'value',
                                        aliases => { Diabetes => 'Diabetes Mellitus' },
                                    },
                                },
                            },
                        },
                    ],
                },
            },
        },
    }
);

my $convert = build_convert(
    in_file      => $csv_file,
    mapping_file => $mapping_file,
    sep          => ',',
    method       => 'csv2bff',
);

my $result = $convert->csv2bff;
is( ref $result, 'ARRAY', 'csv2bff returns an arrayref for tabular conversions' );
is( $result->[0]{id}, '00123:baseline', 'csv2bff preserves leading-zero identifiers from raw CSV values' );
ok( exists $result->[0]{info}{CSV_columns}, 'csv2bff keeps source CSV columns by default' );

$convert = build_convert(
    in_file      => $csv_file,
    mapping_file => $mapping_file,
    sep          => ',',
    method       => 'csv2bff',
    source_info  => 0,
);

$result = $convert->csv2bff;
ok( !exists $result->[0]{info}{CSV_columns}, 'csv2bff omits source CSV columns when source_info is disabled' );
is( $result->[0]{id}, '00123:baseline', 'csv2bff still maps regular fields when source_info is disabled' );

done_testing();
