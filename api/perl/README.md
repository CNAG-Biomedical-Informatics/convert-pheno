# README Convert-Pheno-API (Perl version)

Here we provide a light API to enable requests/responses to `Convert::Pheno`. 

At the time of writting this (Jun-2023) the API consists of **very basic functionalities**, but this might change depening on the community adoption.

### Notes:

* The API is built with Mojolicius.
* This API only accepts requests using `POST` http method.
* This API only has one endpoint `/api`.
* `/api` directly receives a `POST` request with the [request body](https://swagger.io/docs/specification/2-0/describing-request-body) (payload) as JSON object. All the needed data are inside the JSON object (i.e., it does not use request parameters). 
* The incoming JSON data are validated against [OpenAPI schema](./openapi.json). However, the validation is superficial (i.e., we don't check clinical data themselves).
    
## Installation 

### From GitHub + CPAN 

First we download ithe needed files:

    wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/perl/cpanfile
    wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/perl/convert-pheno-api
    wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/perl/openapi.json 

Now we install sys-level dependencies:

    sudo apt-get install cpanminus libbz2-dev zlib1g-dev libperl-dev libssl-dev

Now you have two choose between one of the 3 options below:

Option 1: System-level installation:

    echo "requires 'Convert::Pheno';" >> cpanfile
    cpanm --notest --sudo --installdeps .

Option 2: Install the dependencies at `~/perl5`:

    cpanm --local-lib=~/perl5 local::lib && eval $(perl -I ~/perl5/lib/perl5/ -Mlocal::lib)
    echo "requires 'Convert::Pheno';" >> cpanfile
    cpanm --notest --installdeps .

Option 3: Install Convert-Pheno and the dependencies in a "virtual environment" (at `local/`) . We'll be using the module `Carton` for that:

    mkdir local
    cpanm --local-lib=local/ Carton
    export PATH=$PATH:local/bin; export PERL5LIB=local/lib/perl5:$PERL5LIB
    echo "requires 'Convert::Pheno';" >> cpanfile
    carton install

### With Docker

Please see installation instructions [here](https://github.com/CNAG-Biomedical-Informatics/convert-pheno#containerized-recommended-method).

## How to run

### Non-containerized version

With `morbo` for development:

    $ morbo convert-pheno-api # development (default: port 3000)
    
If you installed it in a local environment then use `carton exec -- `:

    $ carton exec -- morbo convert-pheno-api

If you want to use a self-signed certificate:

    $ morbo convert-pheno-api daemon -l https://*:3000

or with `hypnotoad`:

    $ hypnotoad convert-pheno-api # production (https://localhost:8080)

### Containerized version

With `morbo` for development:

    $ docker container run -p 3000:3000 --name convert-pheno-morbo cnag/convert-pheno:latest morbo share/api/perl/convert-pheno-api

If you want to use a self-signed certificate:

    $ docker container run -p 3000:3000 --name convert-pheno-morbo cnag/convert-pheno:latest morbo share/api/perl/convert-pheno-api daemon -l https://*:3000

or with `hypnotoad`:

    $ docker container run -p 8080:8080 --name convert-pheno-hypnptoad cnag/convert-pheno:latest hypnotoad -f share/api/perl/convert-pheno-api

## Examples

### POST with a data file (Beacon v2 to Phenopacket v2)

    $ curl -d "@data.json" -H 'Content-Type: application/json' -X POST http://localhost:3000/api
    $ curl -k -d "@data.json" -H 'Content-Type: application/json' -X POST https://localhost:3000/api # -k tells cURL to accept self-signed certificates

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
