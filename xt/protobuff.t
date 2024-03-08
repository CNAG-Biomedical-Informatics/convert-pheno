#!/usr/bin/env perl

# mrueda : Oct-18-22
# This test is meant to be run locally during develpment
# Otherwise we will need to unnecessarily deploy Inline/protobuff/Python,etc

use strict;
use warnings;
use lib ( './lib', '../lib' );
use feature qw(say);
use Data::Dumper;
use Test::More tests => 5;
use Convert::Pheno;

use_ok('Convert::Pheno') or exit;

my $input = {
    bff2pxf => {
        out => 't/bff2pxf/out/pxf.json'
    },
    omop2pxf => {
        out => 't/omop2pxf/out/pxf.json'
    },
    redcap2pxf => {
        out => 't/redcap2pxf/out/pxf.json'
    },
    cdisc2pxf => {
       out => 't/cdisc2pxf/out/pxf.json'
    }
};

for my $method ( sort keys %{$input} ) {
    ok( validate_pxf( $input->{$method}{out} ), qq(protobuff -> $method) );
}

use Inline Python => <<'END_OF_PYTHON_CODE';

from google.protobuf.json_format import Parse
from phenopackets import Phenopacket
import json
#from pprint import pprint
#import sys
#print(sys.path)

def validate_pxf(input_file):

    # Opening JSON file
    f = open(input_file)

    # returns JSON object as 
    # a dictionary
    data = json.load(f)

    # Iterating through the json list
    for i, row in enumerate(data):
    #    print('Row %4d:' % i)
    #    pprint(row)
        phenopacket = Parse(message=Phenopacket(), text=json.dumps(row))

    # Closing file
    f.close()

    # Parsing phenopackets from json
    #with open('pxf.json', 'r') as jsfile:
    #    phenopacket = Parse(message=Phenopacket(), text=jsfile.read())

    # Return 1 for Perl
    return 1

END_OF_PYTHON_CODE
