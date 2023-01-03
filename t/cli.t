#!/usr/bin/env perl
use strict;
use warnings;
use lib ( './lib', '../lib' );
use feature qw(say);
use Data::Dumper;
use Convert::Pheno;
use Test::More tests => 9;
use File::Compare;

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
        redcap_config     => 't/redcap2bff/in/redcap_3tr_config.yaml',
        sep => undef,
        out => 't/redcap2bff/out/individuals.json'
    },
    redcap2pxf => {
        in_file           => 't/redcap2bff/in/Data_table_3TR_IBD_dummydata.csv',
        redcap_dictionary =>
't/redcap2bff/in/3TRKielTemplateExport01072022_DataDictionary_2022-07-03.csv',
        redcap_config     => 't/redcap2bff/in/redcap_3tr_config.yaml',
        sep => undef,
        out => 't/redcap2pxf/out/pxf.json'
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
        redcap_config     => 't/redcap2bff/in/redcap_3tr_config.yaml',
        sep => undef,
        out => 't/cdisc2bff/out/individuals.json'
    },
    cdisc2pxf => {
        in_file =>
          't/cdisc2bff/in/3TRKielTemplateExpor_CDISC_ODM_2022-09-27_1822.xml',
        redcap_dictionary =>
't/redcap2bff/in/3TRKielTemplateExport01072022_DataDictionary_2022-07-03.csv',
        redcap_config     => 't/redcap2bff/in/redcap_3tr_config.yaml',
        sep => undef,
        out => 't/cdisc2pxf/out/pxf.json'
    }
};

#for my $method (qw/redcap2bff/){
for my $method ( sort keys %{$input} ) {

    #say "################";
    my $convert = Convert::Pheno->new(
        {
            in_file  => $input->{$method}{in_file},
            in_files => $method =~ m/^omop2/
            ? $input->{$method}{in_files}
            : undef,
            redcap_dictionary => $input->{$method}{redcap_dictionary},
            redcap_config => $input->{$method}{redcap_config},
            in_textfile       => 1,
            sep               => $input->{$method}{sep},
            test              => 1,
            method            => $method
        }
    );
    dump_file(
        {
            filename => 't/test.json',
            data     => $convert->$method,
            format   => 'json'
        }
    );
    ok( compare( $input->{$method}{out}, 't/test.json' ) == 0, $method );
}

#########
sub dump_file {

    my $arg = shift;
    if ( $arg->{format} eq 'json' ) {
        write_json( { filename => $arg->{filename}, data => $arg->{data} } );
    }
    else {
        write_yaml( { filename => $arg->{filename}, data => $arg->{data} } );
    }
    return 1;
}
