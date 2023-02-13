#!/usr/bin/env perl
use strict;
use warnings;
use lib ( './lib', '../lib' );
use feature qw(say);
use Data::Dumper;
use File::Temp qw{ tempfile };    # core
use Test::More tests => 9;
use File::Compare;
use Convert::Pheno;

use_ok('Convert::Pheno') or exit;

my $input = {
    bff2pxf => {
        in_file           => 't/bff2pxf/in/individuals.json',
        redcap_dictionary => undef,
        sep               => undef,
        out               => 't/bff2pxf/out/pxf.json'
    },
    pxf2bff => {
        in_file           => 't/pxf2bff/in/all.json',
        redcap_dictionary => undef,
        sep               => undef,
        out               => 't/pxf2bff/out/individuals.json'
    },
    redcap2bff => {
        in_file           => 't/redcap2bff/in/Data_table_3TR_IBD_dummydata.csv',
        redcap_dictionary =>
't/redcap2bff/in/3TRKielTemplateExport01072022_DataDictionary_2022-07-03.csv',
        mapping_file         => 't/redcap2bff/in/redcap_3tr_mapping.yaml',
        self_validate_schema => 1,       # SELF-VALIDATE-SCHEMA (OK - ONLY ONCE)
        sep                  => undef,
        out                  => 't/redcap2bff/out/individuals.json'
    },
    redcap2pxf => {
        in_file           => 't/redcap2bff/in/Data_table_3TR_IBD_dummydata.csv',
        redcap_dictionary =>
't/redcap2bff/in/3TRKielTemplateExport01072022_DataDictionary_2022-07-03.csv',
        mapping_file => 't/redcap2bff/in/redcap_3tr_mapping.yaml',
        sep          => undef,
        out          => 't/redcap2pxf/out/pxf.json'
    },
    omop2bff => {
        in_file           => undef,
        in_files          => ['t/omop2bff/in/dump.sql'],
        sep               => ',',
        redcap_dictionary => undef,
        out               => 't/omop2bff/out/individuals.json'
    },
    omop2pxf => {
        in_file           => undef,
        in_files          => ['t/omop2bff/in/dump.sql'],
        sep               => ',',
        redcap_dictionary => undef,
        out               => 't/omop2pxf/out/pxf.json'
    },
    cdisc2bff => {
        in_file =>
          't/cdisc2bff/in/3TRKielTemplateExpor_CDISC_ODM_2022-09-27_1822.xml',
        redcap_dictionary =>
't/redcap2bff/in/3TRKielTemplateExport01072022_DataDictionary_2022-07-03.csv',
        mapping_file => 't/redcap2bff/in/redcap_3tr_mapping.yaml',
        sep          => undef,
        out          => 't/cdisc2bff/out/individuals.json'
    },
    cdisc2pxf => {
        in_file =>
          't/cdisc2bff/in/3TRKielTemplateExpor_CDISC_ODM_2022-09-27_1822.xml',
        redcap_dictionary =>
't/redcap2bff/in/3TRKielTemplateExport01072022_DataDictionary_2022-07-03.csv',
        mapping_file => 't/redcap2bff/in/redcap_3tr_mapping.yaml',
        sep          => undef,
        out          => 't/cdisc2pxf/out/pxf.json'
    }
};

#for my $method (qw/redcap2bff/){
for my $method ( sort keys %{$input} ) {

    # Create Temporary file
    my ( undef, $tmp_file ) =
      tempfile( DIR => 't', SUFFIX => ".json", UNLINK => 1 );
    my $convert = Convert::Pheno->new(
        {
            in_file  => $input->{$method}{in_file},
            in_files => $method =~ m/^omop2/
            ? $input->{$method}{in_files}
            : [],
            redcap_dictionary    => $input->{$method}{redcap_dictionary},
            mapping_file         => $input->{$method}{mapping_file},
            self_validate_schema => $input->{$method}{self_validate_schema},
            schema_file          => 'schema/mapping.json',
            in_textfile          => 1,
            omop_tables          => [],
            sep                  => $input->{$method}{sep},
            test                 => 1,
            search               => 'exact',
            method               => $method
        }
    );
    io_yaml_or_json(
        {
            filepath => $tmp_file,
            data     => $convert->$method,
            mode     => 'write'
        }
    );
    ok( compare( $input->{$method}{out}, $tmp_file ) == 0, $method );
}
