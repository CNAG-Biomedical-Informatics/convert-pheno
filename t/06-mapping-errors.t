#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use File::Temp qw(tempfile);
use Test::Exception tests => 6;
use Test::ConvertPheno qw(build_convert load_data_file write_json_file);

my %err = (
    1 => 'typos',
    2 => 'additionalProperties: false',
    3 => 'expected array got string',
    4 => 'radio property is not nested',
    5 => 'value not allowed for project.source',
);

for my $err ( 1 .. 5 ) {
    my $convert = build_convert(
        in_file           => 't/redcap2bff/in/redcap_data.csv',
        redcap_dictionary => 't/redcap2bff/in/redcap_dictionary.csv',
        mapping_file      => "t/redcap2bff/err/redcap_mapping_err$err.yaml",
        method            => 'redcap2bff',
    );
    dies_ok { $convert->redcap2bff }
      "dies for mapping error $err: $err{$err}";
}

{
    my $entity_mapping = load_data_file('t/csv2bff/in/csv_mapping.yaml');
    my $flat_mapping = {
        %{ $entity_mapping->{beacon}{individuals} },
        project => $entity_mapping->{project},
    };

    my ( $fh, $mapping_file ) = tempfile( DIR => '/tmp', SUFFIX => '.json', UNLINK => 1 );
    close $fh;
    write_json_file( $mapping_file, $flat_mapping );

    my $convert = build_convert(
        in_file      => 't/csv2bff/in/csv_data.csv',
        mapping_file => $mapping_file,
        sep          => ',',
        method       => 'csv2bff',
    );

    dies_ok { $convert->csv2bff }
      'dies for flat legacy mapping files without a top-level beacon section';
}
