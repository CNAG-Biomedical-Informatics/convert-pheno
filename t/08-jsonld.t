#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use Test::Exception;
use Test::ConvertPheno qw(build_convert read_first_json_object);

my $has_jsonld = eval { require JSONLD; 1 } ? 1 : 0;

my $bff = read_first_json_object('t/bff2pxf/in/individuals.json');
my $pxf = read_first_json_object('t/pxf2bff/in/pxf.json');

for my $case (
    {
        name   => 'bff2jsonld',
        method => 'bff2jsonld',
        data   => $bff,
        key    => 'bff:sex',
    },
    {
        name   => 'pxf2jsonld',
        method => 'pxf2jsonld',
        data   => $pxf,
        key    => 'https://phenopacket-schema.readthedocs.io/en/latest/schema.html#version-2-0/subject',
    },
  )
{
    my $convert = build_convert(
        in_textfile => 0,
        data        => $case->{data},
        method      => $case->{method},
    );

    if ($has_jsonld) {
        my $got = $convert->${ \$case->{method} };
        ok( ref($got) eq 'HASH', "$case->{name} returns a hashref" );
        ok( exists $got->{ $case->{key} }, "$case->{name} includes expected compacted key" );
    }
    else {
        dies_ok { $convert->${ \$case->{method} } } "$case->{name} dies without JSONLD dependency";
    }
}

done_testing();
