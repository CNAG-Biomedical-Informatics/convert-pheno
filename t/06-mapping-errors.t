#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::Exception tests => 5;
use Test::ConvertPheno qw(build_convert);

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
