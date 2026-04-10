In some workflows it is more convenient to send conversion requests over HTTP instead of calling the module directly. For that case, `Convert-Pheno` includes a lightweight REST API.

## Basic request

Send a `POST` request to `/api` with a JSON body:

```bash
curl -d "@data.json" -H 'Content-Type: application/json' -X POST http://localhost:3000/api
```

Example payload:

```json
{
  "data": { "...": "..." },
  "method": "pxf2bff",
  "ohdsi_db": false
}
```

The response is the result of running the requested `Convert::Pheno` method.

??? Note "Interactive API specification"
    Interactive documentation is available [here](redoc-static.html), built with [ReDoc](https://redocly.github.io/redoc/).

## Available implementations

The repository currently includes two API wrappers:

- Perl: [api/perl](https://github.com/cnag-biomedical-informatics/convert-pheno/tree/main/api/perl)
- Python: [api/python](https://github.com/cnag-biomedical-informatics/convert-pheno/tree/main/api/python)

The Perl implementation is the direct wrapper around the main module. The Python implementation exists for interoperability, but the core conversion logic still lives in Perl.

## Deployment note

This API is intended to run on a machine where `Convert-Pheno` and its dependencies are already installed. In practice, the containerized setup is the easiest way to expose it as a local service.

See:

- [Download & Installation](download-and-installation.md)
- [Containerized installation](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/docker/README.md)
