#!/usr/bin/env perl
use strict;
use warnings;
use lib ( './lib', '../lib' );
use feature qw(say);
use Convert::Pheno;
use Test::Exception tests => 2;

my $input = {
    redcap2bff => {
        in_file           => 't/redcap2bff/in/Data_table_3TR_IBD_dummydata.csv',
        redcap_dictionary =>
't/redcap2bff/in/3TRKielTemplateExport01072022_DataDictionary_2022-07-03.csv',
        mapping_file         => 't/redcap2bff/err/redcap_3tr_mapping_err.yaml',
        self_validate_schema => 0,                                             # SELF-VALIDATE-SCHEMA (OK - ONLY ONCE)
        sep                  => undef,
        out                  => 't/redcap2bff/out/individuals.json'
    }
};

my %err = ( '1' => 'typo', '2' => 'additionalProperties: false' );

for my $method ( sort keys %{$input} ) {
    for my $err ( 1 .. 2 ) {
        my $convert = Convert::Pheno->new(
            {
                in_file           => $input->{$method}{in_file},
                in_files          => undef,
                redcap_dictionary => $input->{$method}{redcap_dictionary},
                mapping_file      => 't/redcap2bff/err/redcap_3tr_mapping_err'
                  . $err . '.yaml',
                self_validate_schema => $input->{$method}{self_validate_schema},
                in_textfile          => 1,
                sep                  => $input->{$method}{sep},
                test                 => 1,
                method               => $method
            }
        );
        dies_ok { $convert->$method }
        'expecting to die by mapping error: ' . $err{$err};
    }
}
