#!/usr/bin/env perl
use strict;
use warnings;
use lib ( './lib', '../lib' );
use feature    qw(say);
use File::Temp qw{ tempfile };    # core
use Data::Dumper;
use File::Spec::Functions qw(catdir catfile);
use Test::More tests => 7;
use Test::Exception;
use Test::Warn;
use File::Compare;
use Convert::Pheno;

use_ok('Convert::Pheno') or exit;

# NB: Define constants to allow passing tests
use constant HAS_IO_SOCKET_SSL => defined eval { require IO::Socket::SSL };
use constant IS_WINDOWS        => ( $^O eq 'MSWin32' || $^O eq 'cygwin' ) ? 1 : 0 ;
my $SELF_VALIDATE = IS_WINDOWS ? 0 : HAS_IO_SOCKET_SSL ? 1 : 0;
$SELF_VALIDATE  = 0;

my $input = {
    redcap2bff => {
        in_file              => 't/redcap2bff/in/redcap_data.csv',
        redcap_dictionary    => 't/redcap2bff/in/redcap_dictionary.csv',
        mapping_file         => 't/redcap2bff/in/redcap_mapping.yaml',
        schema_file          => 'share/schema/mapping.json',
       # self_validate_schema => $SELF_VALIDATE,
        self_validate_schema => 0,
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
            in_files             => [],
            redcap_dictionary    => $input->{$method}{redcap_dictionary},
            mapping_file         => $input->{$method}{mapping_file},
            self_validate_schema => $input->{$method}{self_validate_schema},
            schema_file          => $input->{$method}{schema_file},
            in_textfile          => 1,
            sep                  => $input->{$method}{sep},
            test                 => 1,
            out_file             => $tmp_file,
            omop_tables          => [],
            debug                => undef,
            search               => 'exact',
            verbose              => undef,
            method               => $method
        }
    );
    io_yaml_or_json(
        {
            filepath => $tmp_file,
            data     => $convert->$method,
            mode     => 'write'
        }
    ) and say "io yaml passed";
    ok( compare( $input->{$method}{out}, $tmp_file ) == 0, $method );
}

########################
# Miscellanea die errors
########################

my %err = (
    'ERR1' => '<in_file> does not exist',
    'ERR2' => '<mapping_file> does not exist',
    'ERR3' => 'cannot locate object <method> via package Convert::Pheno',
    'ERR4' =>
'<malformed.json> "type": "foo" does not self-validate against JSON Schema'
);
for my $method ( sort keys %{$input} ) {
    for my $err ( keys %err ) {
        my $convert = Convert::Pheno->new(
            {
                in_file => $err eq 'ERR1' ? 'dummy'
                : $input->{$method}{in_file},
                in_files          => [],
                redcap_dictionary => $input->{$method}{redcap_dictionary},
                mapping_file      => $err eq 'ERR2' ? 'dummy'
                : $input->{$method}{mapping_file},
                self_validate_schema => ( $err eq 'ERR4' && $SELF_VALIDATE ) ? 1
                : 0,
                schema_file => $err eq 'ERR4' ? 't/schema/malformed.json'
                : $input->{$method}{schema_file},
                in_textfile => 1,
                omop_tables => [],
                search      => 'exact',
                sep         => $input->{$method}{sep},
                test        => 1,
                method      => $err eq 'ERR3' ? 'foo2bar' : $method
            }
        );
        dies_ok { $convert->$method } qq(expecting to die by error: $err{$err});
    }
}

###################
# Miscellanea warns
###################
{
    my $input = {
        omop2bff => {
            in_file  => undef,
            in_files => [
                't/omop2bff/in/CONCEPT.csv', 't/omop2bff/in/MEASUREMENT.csv',
                't/omop2bff/in/PERSON.csv',  't/omop2bff/in/DUMMY.csv'
            ],
        }
    };
    my $method = 'omop2bff';

    # Create Temporary file
    my ( undef, $tmp_file ) =
      tempfile( DIR => 't', SUFFIX => ".json", UNLINK => 1 );

    my $convert = Convert::Pheno->new(
        {
            in_files    => $input->{$method}{in_files},
            in_textfile => 1,
            search      => 'exact',
            stream      => 0,
            out_file    => $tmp_file,
            omop_tables => [],
            ohdsi_db    => 1,                             # Need ohdsi_db as we deal with few rows
            method      => $method
        }
    );
  SKIP: {
        skip qq{because 'db/ohdsi.db' is required with <ohdsi_db>}, 1
          unless -f 'db/ohdsi.db';
        warning_is { $convert->$method }
        qq(<DUMMY> is not a valid table in OMOP-CDM\n),
          "expecting warn: <DUMMY> is not a valid table in OMOP-CDM\n";
    }
}
