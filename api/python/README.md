# README Convert-Pheno-API (Python version)

Here we provide a light API to enable requests/responses to `Convert::Pheno`. 

At the time of writting this (Dec-2022) the API consists of **very basic functionalities**, but this might change depening on the community adoption.

### Notes:

* The API is built with FastAPI.
* This API only accepts requests using `POST` http method.
* This API only has one endpoint `/api`.
* `/api` directly receives a `POST` request with the [request body](https://swagger.io/docs/specification/2-0/describing-request-body) (payload) as JSON object. All the needed data are inside the JSON object (i.e., it does not use request parameters).
* The incoming JSON data are validated against OpenAPI schema. However, the validation is superficial (i.e., we don't check clinical data themselves).

## Installation 

## From GitHub + CPAN 

First install sys-level dependencies:

    sudo apt-get install cpanminus libbz2-dev zlib1g-dev libperl-dev python3-pip # sys-level

We'll install Convert-Pheno and the dependencies in a "virtual environment" (at `local/`) . We'll be using the module `Carton` for that:

    wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/python/install.sh
    export PATH=$PATH:local/bin; export PERL5LIB=$(pwd)/local/lib/perl5:$PERL5LIB

    ./install.sh 

### With Docker

Please see installation instructions [here](https://github.com/mrueda/convert-pheno#containerized-recommended-method).

## How to run

### Non-containerized version

With `uvicorn` for development:

    $ uvicorn main:app --reload # development (default: port 8000)

With `uvicorn` for production:

    $ uvicorn main:app 

### Containerized version

With `uvicorn` for development:

    $ docker container run -p 8000:8000 --name convert-pheno-uvicoroxe cnag/convert-pheno:latest uvicorn share.api.python.main:app --host 0.0.0.0

## Examples

### POST with a data file (Beacon v2 to Phenopacket v2)

    $ curl -d "@data.json" -X POST http://localhost:8000/api
    $ curl -k -d "@data.json" -X POST https://localhost:8000/api # -k tells cURL to accept self-signed certificates

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
