#!/usr/bin/env perl
#
#   Example script on how to use Convert::Pheno directly from Perl
#
#   This file is part of Convert::Pheno
#
#   Last Modified: Apr/15/2026
#
#   $VERSION taken from Convert::Pheno
#
#   Copyright (C) 2022-2026 Manuel Rueda - CNAG (manuel.rueda@cnag.eu)
#
#   License: Artistic License 2.0 

use strict;
use warnings;
use JSON::XS;

# Provide the path to <convert-pheno/lib> when running from the repository
# checkout instead of an installed Perl environment.
use lib '../../lib';
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
};

# Create object. Module parameters are passed in one flat hash, unlike the
# structured HTTP API payload.
my $convert = Convert::Pheno->new(
    {
        data   => $my_pxf_json_data,
        method => $method,
        test   => 1,
    }
);

# Run method and print formatted JSON
my $result = $convert->$method;
print JSON::XS->new->canonical->pretty->encode($result);
