#!/usr/bin/env perl
use strict;
use warnings;
use lib ( './lib', '../lib' );
use feature qw(say);
use Data::Dumper;
use JSON::XS;
use Test::More tests => 2;
use Test::Deep;
use Convert::Pheno;

use_ok('Convert::Pheno') or exit;

# Load data
my $bff = bff();
my $pxf = pxf();

# Ignoring variable fields
# https://metacpan.org/pod/Test::Deep
$pxf->{$_} = ignore() for (qw(id metaData));

my $input = { bff2pxf => { data => $bff } };

# Tests
for my $method ( sort keys %{$input} ) {
    my $convert = Convert::Pheno->new(
        {
            in_textfile => 0,
            data        => $input->{$method}{data},
            method      => $method
        }
    );

    #is_deeply( $convert->$method, $pxf, $method );
    cmp_deeply( $convert->$method, $pxf, $method );

}

sub pxf {
    my $str = '
   {
      "diseases" : [],
      "id" : null,
      "measurements" : [
         {
            "assay" : {
               "id" : "LOINC:35925-4",
               "label" : "BMI"
            },
            "value" : {
               "quantity" : {
                  "unit" : {
                     "id" : "NCIT:C49671",
                     "label" : "Kilogram per Square Meter"
                  },
                  "value" : 26.63838307
               }
            }
         },
         {
            "assay" : {
               "id" : "LOINC:3141-9",
               "label" : "Weight"
            },
            "value" : {
               "quantity" : {
                  "unit" : {
                     "id" : "NCIT:C28252",
                     "label" : "Kilogram"
                  },
                  "value" : 85.6358
               }
            }
         },
         {
            "assay" : {
               "id" : "LOINC:8308-9",
               "label" : "Height-standing"
            },
            "value" : {
               "quantity" : {
                  "unit" : {
                     "id" : "NCIT:C49668",
                     "label" : "Centimeter"
                  },
                  "value" : 179.2973
               }
            }
         }
      ],
      "medicalActions" : [
         {
            "procedure" : {
               "code" : {
                  "id" : "OPCS4:L46.3",
                  "label" : "OPCS(v4-0.0):Ligation of visceral branch of abdominal aorta NEC"
               },
               "performed" : {
                  "timestamp" : "1900-01-01T00:00:00Z"
               }
            }
         }
      ],
      "metaData" : null,
      "subject" : {
         "id" : "HG00096",
         "sex" : "MALE",
         "vitalStatus" : {
           "status" : "ALIVE"
         }
      }
   }
';
    return decode_json $str;
}

sub bff {
    my $str = '
  {
    "ethnicity": {
      "id": "NCIT:C42331",
      "label": "African"
    },
    "id": "HG00096",
    "info": {
      "eid": "fake1"
    },
    "interventionsOrProcedures": [
      {
        "procedureCode": {
          "id": "OPCS4:L46.3",
          "label": "OPCS(v4-0.0):Ligation of visceral branch of abdominal aorta NEC"
        }
      }
    ],
    "measures": [
      {
        "assayCode": {
          "id": "LOINC:35925-4",
          "label": "BMI"
        },
        "date": "2021-09-24",
        "measurementValue": {
          "quantity": {
            "unit": {
              "id": "NCIT:C49671",
              "label": "Kilogram per Square Meter"
            },
            "value": 26.63838307
          }
        }
      },
      {
        "assayCode": {
          "id": "LOINC:3141-9",
          "label": "Weight"
        },
        "date": "2021-09-24",
        "measurementValue": {
          "quantity": {
            "unit": {
              "id": "NCIT:C28252",
              "label": "Kilogram"
            },
            "value": 85.6358
          }
        }
      },
      {
        "assayCode": {
          "id": "LOINC:8308-9",
          "label": "Height-standing"
        },
        "date": "2021-09-24",
        "measurementValue": {
          "quantity": {
            "unit": {
              "id": "NCIT:C49668",
              "label": "Centimeter"
            },
            "value": 179.2973
          }
        }
      }
    ],
    "sex": {
      "id": "NCIT:C20197",
      "label": "male"
    }
  }
';
    return decode_json $str;
}
