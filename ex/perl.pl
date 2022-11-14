#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

##############################
# Only if the module WAS NOT #
# installed from CPAN        #
##############################
# - We have to provide the path to <convert-pheno/lib>
use lib '../lib';
use Convert::Pheno;

# Define method
my $method = 'pxf2bff';

# Define data
my $my_pxf_json_data = {
    "phenopacket" => {
        "id"      => "P0007500",
        "subject" => {
            "id"          => "P0007500",
            "dateOfBirth" => "unknown-01-01T00:00:00Z",
            "sex"         => "FEMALE"
        }
    }
  } ;

# Create object
my $convert = Convert::Pheno->new(
    {
        data   => $my_pxf_json_data,
        method => $method
    }
);

# Run method and store result in hashref
my $hashref = $convert->$method;
print Dumper $hashref;
