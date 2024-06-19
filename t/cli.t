#!/usr/bin/env perl
use strict;
use warnings;
use lib ( './lib', '../lib' );
use feature qw(say);
use Data::Dumper;
use File::Temp qw{ tempfile };    # core
use Test::More tests => 16;
use File::Compare;
use Test::Deep;
use Convert::Pheno;
use Convert::Pheno::IO::CSVHandler;

use constant IS_WINDOWS => ( $^O eq 'MSWin32' || $^O eq 'cygwin' ) ? 1 : 0;

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
    pxf2bff_yaml => {
        in_file           => 't/pxf2bff/in/pxf.yaml',
        redcap_dictionary => undef,
        sep               => undef,
        out               => 't/pxf2bff/out/inviduals.yaml'
    },
    redcap2bff => {
        in_file           => 't/redcap2bff/in/redcap_data.csv',
        redcap_dictionary => 't/redcap2bff/in/redcap_dictionary.csv',
        mapping_file      => 't/redcap2bff/in/redcap_mapping.yaml',
        sep               => undef,
        out               => 't/redcap2bff/out/individuals.json'
    },
    redcap2pxf => {
        in_file           => 't/redcap2bff/in/redcap_data.csv',
        redcap_dictionary => 't/redcap2bff/in/redcap_dictionary.csv',
        mapping_file      => 't/redcap2bff/in/redcap_mapping.yaml',
        sep               => undef,
        out               => 't/redcap2pxf/out/pxf.json'
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
        in_file           => 't/cdisc2bff/in/cdisc_odm_data.xml',
        redcap_dictionary => 't/redcap2bff/in/redcap_dictionary.csv',
        mapping_file      => 't/redcap2bff/in/redcap_mapping.yaml',
        sep               => undef,
        out               => 't/cdisc2bff/out/individuals.json'
    },
    cdisc2pxf => {
        in_file           => 't/cdisc2bff/in/cdisc_odm_data.xml',
        redcap_dictionary => 't/redcap2bff/in/redcap_dictionary.csv',
        mapping_file      => 't/redcap2bff/in/redcap_mapping.yaml',
        sep               => undef,
        out               => 't/cdisc2pxf/out/pxf.json'
    },
    bff2csv => {
        in_file => 't/bff2pxf/in/individuals.json',
        sep     => undef,
        out     => 't/bff2csv/out/individuals.csv'
    },
    bff2jsonf => {
        in_file => 't/bff2pxf/in/individuals.json',
        sep     => undef,
        out     => 't/bff2jsonf/out/individuals.fold.json'
    },
    pxf2csv => {
        in_file => 't/pxf2bff/in/pxf.json',
        sep     => undef,
        out     => 't/pxf2csv/out/pxf.csv'
    },
    pxf2jsonf => {
        in_file => 't/pxf2bff/in/pxf.json',
        sep     => undef,
        out     => 't/pxf2jsonf/out/pxf.fold.json'
    },
    csv2bff => {
        in_file      => 't/csv2bff/in/csv_data.csv',
        mapping_file => 't/csv2bff/in/csv_mapping.yaml',
        sep          => ',',
        out          => 't/csv2bff/out/individuals.json'
    },
    csv2pxf => {
        in_file      => 't/csv2bff/in/csv_data.csv',
        mapping_file => 't/csv2bff/in/csv_mapping.yaml',
        sep          => ',',
        out          => 't/csv2pxf/out/pxf.json'
    }
};

#for my $method (qw/pxf2csv/) {
for my $method ( sort keys %{$input} ) {
    $method = $method eq 'pxf2bff_yaml' ? 'pxf2bff' : $method;

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
  SKIP: {

        # Fails
        # non-omop in Github windows-latest
        # omop in Win32 CPAN
        skip
qq{Files <$input->{$method}{out}> <$tmp_file> are supposedly identical yet compare fails with windows-latest|Win32},
          1
          if IS_WINDOWS;

        if (   $method !~ m/^omop2/
            && $method ne 'bff2csv'
            && $method ne 'pxf2csv' )
        {
            io_yaml_or_json(
                {
                    filepath => $tmp_file,
                    data     => $convert->$method,
                    mode     => 'write'
                }
            );
        }
        elsif ( $method eq 'bff2csv' || $method eq 'pxf2csv' ) {
            my $data = $convert->$method;
            $tmp_file = $tmp_file . '.csv';
            write_csv(    # Print data as CSV
                {
                    sep      => ';',
                    filepath => $tmp_file,
                    headers  => get_headers($data),
                    data     => $data
                }
            );
        }
        else {
            $convert->$method;
        }

        # Compare the files
        if ( compare( $input->{$method}{out}, $tmp_file ) != 0 ) {
            my $expected_content = read_file( $input->{$method}{out} );
            my $actual_content   = read_file($tmp_file);

            # Decode JSON content
            my $expected_json = decode_json($expected_content);
            my $actual_json   = decode_json($actual_content);

            diag("Error found in method $method");

            # Use Test::Deep to compare data structures
            cmp_deeply( $actual_json, $expected_json,
                "Check if actual output matches expected for $method" );
        }
        ok( compare( $input->{$method}{out}, $tmp_file ) == 0, $method );
        unlink($tmp_file) if -f $tmp_file;
    }
}

sub read_file {
    my ($file) = @_;
    open my $fh, '<', $file or die "Could not open file '$file': $!";
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content;
}
