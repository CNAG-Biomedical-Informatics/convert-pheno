In some workflows it is more convenient to send conversion requests over HTTP instead of calling the module directly. For that case, `Convert-Pheno` includes a lightweight REST API.

## Basic request

Send a `POST` request to `/api` with a JSON body:

```bash
curl -d "@data.json" -H 'Content-Type: application/json' -X POST http://localhost:3000/api
```

Example payload:

```json
{
  "conversion": "pxf2bff",
  "input": {
    "data": { "...": "..." }
  },
  "output": {
    "entities": ["individuals"]
  },
  "options": {
    "ohdsi_db": false
  }
}
```

The response is a JSON envelope with `ok`, `data`, and `meta.conversion`.

??? Note "OpenAPI specification"
    The source schema for the Perl/Mojolicious wrapper lives in [api/perl/openapi.json](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/api/perl/openapi.json).

## Recommended API routes

The HTTP API works best for **self-contained payloads** where the request already carries the data needed for conversion.

| Input family | HTTP API status | Why |
| --- | --- | --- |
| `BFF` | Recommended | Small JSON payloads are natural to send over HTTP |
| `PXF` | Recommended | Small JSON payloads are natural to send over HTTP |
| `OMOP-CDM` | Recommended with care | Acceptable when the client transposes query results into the JSON shape expected by the API |
| `CSV` | Not recommended | Mapping-file-based conversion depends on extra artifacts and file semantics that are awkward to serialize into a clean public API |
| `REDCap` | Not recommended | Requires both project data and a REDCap dictionary plus mapping-file context |
| `CDISC-ODM` | Not recommended | Follows the same mapping-file-driven pattern as REDCap |

For `CSV`, `REDCap`, and `CDISC-ODM`, the **CLI is the preferred interface**. Those routes are better treated as file workflows than as public HTTP workflows.

## Available implementations

The repository currently includes two API wrappers:

- Perl: [api/perl](https://github.com/cnag-biomedical-informatics/convert-pheno/tree/main/api/perl)
- Python: [api/python](https://github.com/cnag-biomedical-informatics/convert-pheno/tree/main/api/python)

The Perl implementation is the direct wrapper around the main module. The Python implementation exists for interoperability and calls the Perl conversion layer through an internal JSON bridge, so the core conversion logic still lives in Perl.

## Deployment note

This API is intended to run on a machine where `Convert-Pheno` and its dependencies are already installed. In practice, the containerized setup is the easiest way to expose it as a local service.

See:

- [Download & Installation](download-and-installation.md)
- [Containerized installation](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/docker/README.md)
