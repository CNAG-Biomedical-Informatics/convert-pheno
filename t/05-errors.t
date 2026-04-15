#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use Test::Exception;
use Test::ConvertPheno qw(build_convert is_ld_arch);

BEGIN {
    if ( is_ld_arch() ) {
        require Test::More;
        Test::More::plan(
            skip_all => 'Skipping tests on ld architectures due to known issues'
        );
        exit;
    }
}

my $base = {
    in_file           => 't/redcap2bff/in/redcap_data.csv',
    redcap_dictionary => 't/redcap2bff/in/redcap_dictionary.csv',
    mapping_file      => 't/redcap2bff/in/redcap_mapping.yaml',
    schema_file       => 'share/schema/mapping.json',
    method            => 'redcap2bff',
};

{
    my %err = (
        ERR1 => build_convert( %{$base}, in_file => 'dummy' ),
        ERR2 => build_convert( %{$base}, mapping_file => 'dummy' ),
        ERR3 => build_convert( %{$base}, method => 'foo2bar' ),
        ERR4 => build_convert( %{$base}, schema_file => 'dummy' ),
    );

    for my $name ( sort keys %err ) {
        my $convert = $err{$name};
        dies_ok { $convert->redcap2bff } "dies for $name";
    }
}

{
    my $convert = build_convert(
        in_file       => 't/csv2bff/in/csv_data.csv',
        mapping_file  => 't/csv2bff/in/csv_mapping.csv',
        sep           => ';',
        method        => 'csv2bff',
    );
    dies_ok { $convert->csv2bff } 'dies when CSV separator is wrong';
}

done_testing();
