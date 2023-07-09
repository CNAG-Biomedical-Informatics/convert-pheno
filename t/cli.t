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
        in_file           => 't/pxf2bff/in/pxf.json',
        redcap_dictionary => undef,
        sep               => undef,
        out               => 't/pxf2bff/out/individuals.json'
    },
    redcap2bff => {
        in_file           => 't/redcap2bff/in/redcap_data.csv',
        redcap_dictionary =>
't/redcap2bff/in/redcap_dictionary.csv',
        mapping_file         => 't/redcap2bff/in/redcap_mapping.yaml',
        sep                  => undef,
        out                  => 't/redcap2bff/out/individuals.json'
    },
    redcap2pxf => {
        in_file           => 't/redcap2bff/in/redcap_data.csv',
        redcap_dictionary =>
't/redcap2bff/in/redcap_dictionary.csv',
        mapping_file => 't/redcap2bff/in/redcap_mapping.yaml',
        sep          => undef,
        out          => 't/redcap2pxf/out/pxf.json'
    },
    omop2bff => {
        in_file           => undef,
        in_files          => ['t/omop2bff/in/omop_cdm_eunomia.sql'],
        sep               => ',',
        redcap_dictionary => undef,
        out               => 't/omop2bff/out/individuals.json'
    },
    omop2pxf => {
        in_file           => undef,
        in_files          => ['t/omop2bff/in/omop_cdm_eunomia.sql'],
        sep               => ',',
        redcap_dictionary => undef,
        out               => 't/omop2pxf/out/pxf.json'
    },
    cdisc2bff => {
        in_file =>
          't/cdisc2bff/in/cdisc_odm_data.xml',
        redcap_dictionary =>
't/redcap2bff/in/redcap_dictionary.csv',
        mapping_file => 't/redcap2bff/in/redcap_mapping.yaml',
        sep          => undef,
        out          => 't/cdisc2bff/out/individuals.json'
    },
    cdisc2pxf => {
        in_file =>
          't/cdisc2bff/in/cdisc_odm_data.xml',
        redcap_dictionary =>
't/redcap2bff/in/redcap_dictionary.csv',
        mapping_file => 't/redcap2bff/in/redcap_mapping.yaml',
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
            self_validate_schema => 0,
            schema_file          => 'share/schema/mapping.json',
            in_textfile          => 1,
            stream               => 0,
            omop_tables          => [],
            out_file             => $tmp_file,
            sep                  => $input->{$method}{sep},
            test                 => 1,
            search               => 'exact',
            method               => $method
        }
    );
    if ( $method !~ m/^omop2/ ) {
        io_yaml_or_json(
            {
                filepath => $tmp_file,
                data     => $convert->$method,
                mode     => 'write'
            }
        )
    } 
    else { $convert->$method }
    ok( compare( $input->{$method}{out}, $tmp_file ) == 0, $method );
}
