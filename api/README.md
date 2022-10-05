# README Convert-Pheno-API

Here we provide a light API to enable requests/responses to `Convert::Pheno`. 

At the time of writting this (Sep-2022) the API consists of **very basic functionalities**, but this might change (i.e., switch to OpenAPI specification) dependeping on community adoption.

### Notes:

* This API only accepts requests using `POST` http method.
* This API only has one endpoint `/individuals`.
    
## Installation

    $ cpanm --sudo Mojolicious Convert::Pheno

## How to run

    $ morbo convert-pheno-api # development (default: port 3000)
or 

    $ hypnotoad convert-pheno-api # production (port 8080)


## Examples

### POST with a data file (Beacon v2 to Phenopacket v2)

   $ curl -d "@data.json" -X POST http://localhost:3000/individuals

[data.json](data.json) contents:
```
{
  "method": "bff2pfx",
  "data": {
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
}
```
