# Convert-Pheno API (Python)

This is a small, JSON-only FastAPI server. It sends conversion requests to the
Perl implementation rather than implementing the conversions again in Python.

> **Planned deprecation:** This Python HTTP API is retained temporarily. New
> integrations should use the Mojolicious API, which supports both JSON and file
> uploads. The Python module binding will remain available.

## Run locally

From a Convert-Pheno source checkout:

```bash
cd api/python
uvicorn main:app --host 127.0.0.1 --port 8000 --reload
```

Endpoints:

- `GET /api/health`
- `GET /api/conversions`
- `POST /api/conversions/{conversion}`

Example:

```bash
curl -H 'Content-Type: application/json' \
  -d '{"input":{"data":{"phenopacket":{"id":"P1"}}},"output":{"entities":["individuals"]},"options":{}}' \
  http://127.0.0.1:8000/api/conversions/pxf2bff
```

The conversion list includes only routes that accept JSON. This server does not
accept file uploads. Use the Mojolicious API or Workbench for mapping files and
multi-file inputs. Use the CLI for streaming or large datasets.
