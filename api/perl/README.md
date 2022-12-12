# README Convert-Pheno-API (Perl version)

Here we provide a light API to enable requests/responses to `Convert::Pheno`. 

At the time of writting this (Fall-2022) the API consists of **very basic functionalities**, but this might change depening on the community adoption.

### Notes:

* The API is built with Mojolicius.
* This API only accepts requests using `POST` http method.
* This API only has one endpoint `/api`.
* `/api` directly receives a `POST` request with the [request body](https://swagger.io/docs/specification/2-0/describing-request-body) (payload) as JSON object. All the needed data are inside the JSON object (i.e., it does not use request parameters). 
    
## Installation 

### From CPAN 

    $ cpanm --sudo Convert::Pheno # Once the paper is published !!!

### With Docker

Please see installation instructions [here](https://github.com/mrueda/convert-pheno#containerized).

## How to run

### Non-containerized version

With `morbo` for development:

    $ morbo convert-pheno-api # development (default: port 3000)

If you want to use a self-signed certificate:

    $ morbo convert-pheno-api daemon -l https://*:3000

or with `hypnotoad`:

    $ hypnotoad convert-pheno-api # production (https://localhost:8080)

### Containerized version

With `morbo` for development:

    $ docker container run -p 3000:3000 --name convert-pheno-dev cnag/convert-pheno:latest morbo api/perl/convert-pheno-api

If you want to use a self-signed certificate:

    $ docker container run -p 3000:3000 --name convert-pheno-dev cnag/convert-pheno:latest morbo api/perl/convert-pheno-api daemon -l https://*:3000

or with `hypnotoad`:

    $ docker container run -p 8080:8080 --name convert-pheno-pro cnag/convert-pheno:latest hypnotoad -f api/perl/convert-pheno-api

## Examples

### POST with a data file (Beacon v2 to Phenopacket v2)

    $ curl -d "@data.json" -X POST http://localhost:3000/api
    $ curl -k -d "@data.json" -X POST https://localhost:3000/api # -k tells cURL to accept self-signed certificates

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
