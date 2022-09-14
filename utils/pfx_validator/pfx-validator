#!/usr/bin/env perl
#
# Author: Manuel Rueda <manuel.ruedal@cnag.crg.eu>
# Date  : 14-Sep-2022

use strict;
use warnings;
use Path::Tiny;
use JSON::XS;
use JSON::Validator;

die "Please provide a <pfx.json> file as input" unless @ARGV;

# Load schema
my $schema = read_json("phenopacket-schema-2-0.json");
my $validator = JSON::Validator->new($schema);

# Load your data
my $data = read_json($ARGV[0]);

# Validate data
my @errors = $validator->validate($data);

# Die if errors were found
die "@errors" if @errors;

sub read_json {

    my $json_file = shift;
    my $str       = path($json_file)->slurp_utf8;
    my $json      = decode_json($str);           # Decode to Perl data structure
    return $json;
}
