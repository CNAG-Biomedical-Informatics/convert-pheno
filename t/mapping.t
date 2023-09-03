#!/usr/bin/env perl
use strict;
use warnings;
use lib ( './lib', '../lib' );
use feature               qw(say);
use File::Spec::Functions qw(catdir catfile);
use Test::Exception tests => 5;
use Convert::Pheno;

my $input = {
    redcap2bff => {
        in_file           => 't/redcap2bff/in/redcap_data.csv',
        redcap_dictionary =>
't/redcap2bff/in/redcap_dictionary.csv',
        self_validate_schema => 0,
        sep                  => undef,
        out                  => 't/redcap2bff/out/individuals.json'
    }
};

my %err = (
    '1' => 'typos',
    '2' => 'additionalProperties: false',
    '3' => 'expected array got string',
    '4' => 'radio property is not nested',
    '5' => 'value not allowed for project.source',
    '6' => 'invalid ontology'
);

for my $method ( sort keys %{$input} ) {
    for my $err ( 1 .. 5 ) {
        my $convert = Convert::Pheno->new(
            {
                in_file           => $input->{$method}{in_file},
                in_files          => [],
                redcap_dictionary => $input->{$method}{redcap_dictionary},
                mapping_file      => catfile(
                    't/redcap2bff/err/redcap_mapping_err', $err,
                    '.yaml'
                ),
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
