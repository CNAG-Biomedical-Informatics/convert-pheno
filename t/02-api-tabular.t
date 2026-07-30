#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use Test::ConvertPheno
  qw(build_convert temp_output_file write_json_file structured_files_match);

my @datasetjson_files = sort glob 't/datasetjson2bff/in/*.json';

my @cases = (
    {
        name               => 'redcap2bff',
        method             => 'redcap2bff',
        in_file            => 't/redcap2bff/in/redcap_data.csv',
        redcap_dictionary  => 't/redcap2bff/in/redcap_dictionary.csv',
        mapping_file       => 't/redcap2bff/in/redcap_mapping.yaml',
        out_file           => 't/redcap2bff/out/individuals.json',
    },
    {
        name               => 'redcap2pxf',
        method             => 'redcap2pxf',
        in_file            => 't/redcap2bff/in/redcap_data.csv',
        redcap_dictionary  => 't/redcap2bff/in/redcap_dictionary.csv',
        mapping_file       => 't/redcap2bff/in/redcap_mapping.yaml',
        out_file           => 't/redcap2pxf/out/pxf.json',
    },
    {
        name               => 'cdiscodm2bff',
        method             => 'cdiscodm2bff',
        in_file            => 't/cdiscodm2bff/in/cdisc_odm_data.xml',
        redcap_dictionary  => 't/redcap2bff/in/redcap_dictionary.csv',
        mapping_file       => 't/redcap2bff/in/redcap_mapping.yaml',
        out_file           => 't/cdiscodm2bff/out/individuals.json',
    },
    {
        name               => 'cdiscodm2pxf',
        method             => 'cdiscodm2pxf',
        in_file            => 't/cdiscodm2bff/in/cdisc_odm_data.xml',
        redcap_dictionary  => 't/redcap2bff/in/redcap_dictionary.csv',
        mapping_file       => 't/redcap2bff/in/redcap_mapping.yaml',
        out_file           => 't/cdiscodm2pxf/out/pxf.json',
    },
    {
        name               => 'datasetjson2bff',
        method             => 'datasetjson2bff',
        in_files           => \@datasetjson_files,
        out_file           => 't/datasetjson2bff/out/individuals.json',
    },
    {
        name               => 'datasetjson2pxf',
        method             => 'datasetjson2pxf',
        in_files           => \@datasetjson_files,
        out_file           => 't/datasetjson2pxf/out/pxf.json',
    },
    {
        name               => 'fhir2bff',
        method             => 'fhir2bff',
        in_files           => ['t/fhir2bff/in/patient-bundle.json'],
        out_file           => 't/fhir2bff/out/individuals.json',
    },
    {
        name               => 'fhir2pxf',
        method             => 'fhir2pxf',
        in_files           => ['t/fhir2bff/in/patient-bundle.json'],
        out_file           => 't/fhir2pxf/out/pxf.json',
    },
    {
        name               => 'csv2bff',
        method             => 'csv2bff',
        in_file            => 't/csv2bff/in/csv_data.csv',
        mapping_file       => 't/csv2bff/in/csv_mapping.yaml',
        sep                => ',',
        out_file           => 't/csv2bff/out/individuals.json',
    },
    {
        name               => 'csv2pxf',
        method             => 'csv2pxf',
        in_file            => 't/csv2bff/in/csv_data.csv',
        mapping_file       => 't/csv2bff/in/csv_mapping.yaml',
        sep                => ',',
        out_file           => 't/csv2pxf/out/pxf.json',
    },
);

for my $case (@cases) {
    my $tmp_file = temp_output_file();
    my $convert  = build_convert(
        in_file            => $case->{in_file},
        in_files           => $case->{in_files},
        redcap_dictionary  => $case->{redcap_dictionary},
        mapping_file       => $case->{mapping_file},
        sep                => $case->{sep},
        out_file           => $tmp_file,
        method             => $case->{method},
    );

    write_json_file( $tmp_file, $convert->${ \$case->{method} } );

    ok( structured_files_match( $case->{out_file}, $tmp_file ), $case->{name} );
}

done_testing();
