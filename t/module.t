#!/usr/bin/env perl
use strict;
use warnings;
use lib ( './lib', '../lib' );
use feature qw(say);
use Data::Dumper;
use Convert::Pheno;
use JSON::XS;
use Test::More tests => 1;

# Load data
my $bff   = bff();
my $pxf   = pxf();
my $input = { bff2pxf => { data => $bff } };

# Tests
for my $method ( sort keys %{$input} ) {
    say "################";
    my $convert = Convert::Pheno->new(
        {
            in_textfile => 0,
            data        => $input->{$method}{data},
            test        => 1,
            method      => $method
        }
    );
    is_deeply( $convert->$method, $pxf, $method );
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
            "timeObserved" : "2021-09-24",
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
            "timeObserved" : "2021-09-24",
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
            "timeObserved" : "2021-09-24",
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
                  "timestamp" : null
               }
            }
         }
      ],
      "metaData" : null,
      "subject" : {
         "age" : null,
         "id" : "HG00096",
         "sex" : "MALE"
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
