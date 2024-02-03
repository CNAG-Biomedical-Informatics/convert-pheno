#!/usr/bin/env perl
#
#   Example script on how to use Convert::Pheno in Perl
#
#   This file is part of Convert::Pheno
#
#   Last Modified: Dec/14/2022
#
#   $VERSION taken from Convert::Pheno
#
#   Copyright (C) 2022-2024 Manuel Rueda - CNAG (manuel.rueda@cnag.eu)
#
#   License: Artistic License 2.0 

use strict;
use warnings;
use Data::Dumper;

# *** IMPORTANT ***
###############################
# We have to provide the path #
# to <convert-pheno/lib>      #
# if the module WAS NOT       #
# installed from CPAN         #
###############################
use lib '../../lib';             #
###############################
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
