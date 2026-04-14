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
            project => {
                id                        => 'raw_values_test',
                source                    => 'csv',
                ontology                  => 'ncit',
                version                   => 'test-0.1',
                baselineFieldsToPropagate => [],
            },
            beacon => {
                individuals => {
                    id => {
                        fields       => [ 'PatientId', 'EventName' ],
                        targetFields => { primaryKey => 'PatientId' },
                    },
                    sex => {
                        fields => 'Sex',
                    },
                    ethnicity => {
                        fields => 'Ethnicity',
                    },
                    diseases => {
                        fields          => ['Disease_1'],
                        valueTermLabels => { Diabetes => 'Diabetes Mellitus' },
                    },
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

done_testing();
