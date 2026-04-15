# README Convert-Pheno-API (Perl version)

This directory contains the Perl HTTP wrapper around `Convert::Pheno`.

### Notes:

* The API is built with `Mojolicious`.
* The public HTTP contract uses a single `POST /api` endpoint.
* `/api` receives a JSON object with explicit `conversion`, `input`, `output`, and `options` sections.
* Incoming request bodies are validated against [OpenAPI schema](./openapi.json), but only at the payload-shape level.
* The conversion logic still runs in `Convert::Pheno`; this wrapper only exposes it over HTTP.
    
## Installation 

### From GitHub + CPAN 

First we download the needed files:

    wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/perl/cpanfile
    wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/perl/main.pl
    wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/perl/openapi.json 

Now we install sys-level dependencies:

    sudo apt-get install cpanminus libbz2-dev zlib1g-dev libperl-dev

Optional for SSL-backed development features:

    sudo apt-get install libssl-dev

`libssl-dev` is only needed if you want HTTPS support in the Perl wrapper or if
you plan to use `--self-validate-schema` in the same environment.

Install Convert-Pheno and the dependencies at `~/perl5`:

    cpanm --local-lib=~/perl5 local::lib && eval $(perl -I ~/perl5/lib/perl5/ -Mlocal::lib)
    echo "requires 'Convert::Pheno';" >> cpanfile
    cpanm --notest --installdeps .

### With Docker

Please see installation instructions [here](https://github.com/CNAG-Biomedical-Informatics/convert-pheno#containerized-recommended-method).

## How to run

### Non-containerized version

With `morbo` for development:

    $ morbo main.pl # development (default: port 3000)
    
If you want to use a self-signed certificate:

    $ morbo main.pl daemon -l https://*:3000

or with `hypnotoad`:

    $ hypnotoad main.pl # production (https://localhost:8080)

### Containerized version

With `morbo` for development:

    $ docker container run -p 3000:3000 --name convert-pheno-morbo cnag/convert-pheno:latest morbo share/api/perl/main.pl

If you want to use a self-signed certificate:

    $ docker container run -p 3000:3000 --name convert-pheno-morbo cnag/convert-pheno:latest morbo share/api/perl/main.pl daemon -l https://*:3000

or with `hypnotoad`:

    $ docker container run -p 8080:8080 --name convert-pheno-hypnptoad cnag/convert-pheno:latest hypnotoad -f share/api/perl/main.pl

## Examples

### POST with a data file (Beacon v2 to Phenopacket v2)

    $ curl -d "@data.json" -H 'Content-Type: application/json' -X POST http://localhost:3000/api
    $ curl -k -d "@data.json" -H 'Content-Type: application/json' -X POST https://localhost:3000/api # -k tells cURL to accept self-signed certificates

[data.json](data.json) contents:
```json
{
  "conversion": "bff2pxf",
  "input": {
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
  },
  "output": {
    "entities": ["individuals"]
  },
  "options": {
    "ohdsi_db": false
  }
}
```

Successful responses use an envelope:

```json
{
  "ok": true,
  "data": {
    "...": "conversion result"
  },
  "meta": {
    "conversion": "bff2pxf"
  }
}
```

Error responses use the same envelope style with `ok: false` plus an `error` object, and may also include `meta.conversion`.
