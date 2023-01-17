#!/usr/bin/env perl
use strict;
use warnings;
use lib ( './lib', '../lib' );
use feature    qw(say);
use File::Temp qw{ tempfile };    # core
use Data::Dumper;
use File::Spec::Functions qw(catdir catfile);
use Test::More tests => 5;
use Test::Exception;
use File::Compare;
use Convert::Pheno;

use_ok('Convert::Pheno') or exit;

my $input = {
    redcap2bff => {
        in_file           => 't/redcap2bff/in/Data_table_3TR_IBD_dummydata.csv',
        redcap_dictionary =>
't/redcap2bff/in/3TRKielTemplateExport01072022_DataDictionary_2022-07-03.csv',
        mapping_file         => 't/redcap2bff/in/redcap_3tr_mapping.yaml',
        self_validate_schema => 1,                                           # SELF-VALIDATE-SCHEMA (OK - ONLY ONCE)
        sep                  => undef,
        out                  => 't/redcap2bff/out/individuals.json'
    }
};

############################################
# Check that debug|verbose do not interfere
############################################
for my $method ( sort keys %{$input} ) {

    # Create Temporary file
    my ( undef, $tmp_file ) =
      tempfile( DIR => 't', SUFFIX => ".json", UNLINK => 1 );

    #say "################";
    my $convert = Convert::Pheno->new(
        {
            in_file              => $input->{$method}{in_file},
            in_files             => undef,
            redcap_dictionary    => $input->{$method}{redcap_dictionary},
            mapping_file         => $input->{$method}{mapping_file},
            self_validate_schema => $input->{$method}{self_validate_schema},
            in_textfile          => 1,
            sep                  => $input->{$method}{sep},
            test                 => 1,
            debug                => 2,
            verbose              => 1,
            method               => $method

        }
    );
    io_yaml_or_json(
        {
            filename => $tmp_file,
            data     => $convert->$method,
            mode     => 'write'
        }
    );
    ok( compare( $input->{$method}{out}, $tmp_file ) == 0, $method );
}

####################
# Miscellanea errors
####################

my %err = (
    '1' => '<in_file> does not exist',
    '2' => '<mapping_file> does not exist',
    '3' => 'wrong <method>'
);
for my $method ( sort keys %{$input} ) {
    for my $err ( 1 .. 3 ) {
        my $convert = Convert::Pheno->new(
            {
                in_file  => $err == 1 ? 'dummy' : $input->{$method}{in_file},
                in_files => undef,
                redcap_dictionary => $input->{$method}{redcap_dictionary},
                mapping_file      => $err == 2 ? 'dummy' : $input->{$method}{mapping_file},
                self_validate_schema => 0,
                in_textfile          => 1,
                sep                  => $input->{$method}{sep},
                test                 => 1,
                method               => $err == 3 ? 'foo2bar' : $method
            }
        );
        dies_ok { $convert->$method }
        'expecting to die by mapping error: ' . $err{$err};
    }
}
