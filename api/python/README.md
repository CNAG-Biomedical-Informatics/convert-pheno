# README Convert-Pheno-API (Python version)

This directory contains the Python REST wrapper around `Convert::Pheno`.

### Notes:

* The API is built with FastAPI.
* The public REST contract uses a single `POST /api` endpoint.
* `/api` receives a JSON object with explicit `conversion`, `input`, `output`, and `options` sections.
* Incoming request bodies are validated at the payload-shape level before conversion.
* The Python layer calls the Perl conversion code through `api/perl/json_bridge.pl`.
* The conversion logic still runs in Perl; this wrapper only exposes the same REST contract through FastAPI.

## Installation

### From GitHub + CPAN

First install sys-level dependencies:

    sudo apt-get install cpanminus libbz2-dev zlib1g-dev libperl-dev python3-pip # sys-level

We'll install Convert-Pheno and the dependencies in a "virtual environment" (at `local/`). We'll be using the module `Carton` for that:

    wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/python/install.sh
    export PATH=$PATH:local/bin; export PERL5LIB=$(pwd)/local/lib/perl5:$PERL5LIB

    bash install.sh

The installer creates a small local layout with:

- `api/python/main.py`
- `api/perl/json_bridge.pl`
- `lib/convertpheno.py`

### With Docker

Please see installation instructions [here](https://github.com/mrueda/convert-pheno#containerized-recommended-method).

## How to run

### Non-containerized version

With `uvicorn` for development:

    $ cd api/python
    $ uvicorn main:app --reload # development (default: port 8000)

This default `uvicorn` example serves plain HTTP.

With `uvicorn` for production:

    $ cd api/python
    $ uvicorn main:app --host 0.0.0.0

If you need HTTPS, add TLS in the ASGI server configuration or terminate TLS in a reverse proxy in front of FastAPI.

### Containerized version

With `uvicorn` for development:

    $ docker container run -p 8000:8000 --name convert-pheno-uvicorn cnag/convert-pheno:latest uvicorn share.api.python.main:app --host 0.0.0.0

## Examples

### POST with a data file (Beacon v2 to Phenopacket v2)

    $ curl -d "@data.json" -H 'Content-Type: application/json' -X POST http://localhost:8000/api
    $ curl -k -d "@data.json" -H 'Content-Type: application/json' -X POST https://localhost:8000/api # -k tells cURL to accept self-signed certificates

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
