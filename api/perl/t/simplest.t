#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use File::Spec::Functions qw(catfile);
use JSON::XS qw(decode_json);
use Test::More tests => 6;

my $contract_path = catfile( $Bin, '..', 'openapi.json' );
open my $fh, '<', $contract_path or die "Cannot open $contract_path: $!";
local $/;
my $contract = decode_json(<$fh>);
close $fh;

is( $contract->{info}{version}, '0.34_1', 'OpenAPI documents the development version' );
ok( exists $contract->{paths}{'/api/health'}{get}, 'health endpoint is documented' );
ok( exists $contract->{paths}{'/api/conversions'}{get}, 'catalog endpoint is documented' );
ok(
    exists $contract->{paths}{'/api/conversions/{conversion}'}{post},
    'artifact conversion endpoint is documented'
);
ok(
    exists $contract->{paths}{'/api/conversions/{conversion}'}{post}{requestBody}{content}{'multipart/form-data'},
    'multipart conversion requests are documented'
);
ok( !exists $contract->{paths}{'/api'}, 'removed POST /api contract is not published' );
