In some workflows it is more convenient to send conversion requests over an HTTP(S) endpoint instead of calling the module directly. For that case, `Convert-Pheno` includes a lightweight REST API.

## Basic request

Send a `POST` request to `/api` with a JSON body. Local examples below use plain `http://` for simplicity, but the same API can also be exposed over `https://` depending on deployment:

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
    A rendered OpenAPI reference is also available as [Redoc](redoc-static.html).

## JavaScript usage

The REST API is language-agnostic. JavaScript clients can call the same `/api` endpoint with the same JSON request body.

=== "Browser (`fetch`)"

    ```javascript
    async function run() {
      const payload = {
        conversion: "pxf2bff",
        input: {
          data: {
            subject: {
              id: "P0007500",
              sex: "FEMALE"
            }
          }
        },
        output: {
          entities: ["individuals"]
        },
        options: {
          test: true
        }
      };

      const response = await fetch("http://localhost:3000/api", {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify(payload)
      });

      const result = await response.json();

      if (!result.ok) {
        console.error(result.error);
      } else {
        console.log(result.data);
      }
    }

    run();
    ```

    This browser example assumes the API is same-origin with the page, or that the deployment enables CORS.

=== "Node.js (`fetch`)"

    ```javascript
    async function run() {
      const payload = {
        conversion: "pxf2bff",
        input: {
          data: {
            subject: {
              id: "P0007500",
              sex: "FEMALE"
            }
          }
        },
        output: {
          entities: ["individuals"]
        },
        options: {
          test: true
        }
      };

      const response = await fetch("http://localhost:3000/api", {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify(payload)
      });

      const result = await response.json();

      if (!result.ok) {
        throw new Error(result.error.message);
      }

      console.log(result.meta.conversion);
      console.log(result.data);
    }

    run().catch(console.error);
    ```

    Node.js 21+ includes stable built-in `fetch`. Older Node.js versions may require a polyfill such as `undici`.

## Recommended API routes

The REST API works best for **self-contained payloads** where the request already carries the data needed for conversion.

| Input family | REST API status | Why |
| --- | --- | --- |
| `BFF` | Recommended | Small JSON payloads are natural to send over HTTP |
| `PXF` | Recommended | Small JSON payloads are natural to send over HTTP |
| `OMOP-CDM` | Recommended with care | Acceptable when the client transposes query results into the JSON shape expected by the API |
| `CSV` | Not recommended | Mapping-file-based conversion depends on extra artifacts and file semantics that are awkward to serialize into a clean public API |
| `REDCap` | Not recommended | Requires both project data and a REDCap dictionary plus mapping-file context |
| `CDISC-ODM` | Not recommended | Follows the same mapping-file-driven pattern as REDCap |

For `CSV`, `REDCap`, and `CDISC-ODM`, the **CLI is the preferred interface**. Those routes are better treated as file workflows than as public REST workflows.

## Available implementations

The repository currently includes two API wrappers:

- Perl: [api/perl](https://github.com/cnag-biomedical-informatics/convert-pheno/tree/main/api/perl)
- Python: [api/python](https://github.com/cnag-biomedical-informatics/convert-pheno/tree/main/api/python)

The Perl implementation is the direct wrapper around the main module. The Python implementation exists for interoperability and calls the Perl conversion layer through an internal JSON bridge, so the core conversion logic still lives in Perl.

Client applications in JavaScript can consume the same REST API without needing a dedicated JavaScript server wrapper.

## Deployment note

This API is intended to run on a machine where `Convert-Pheno` and its dependencies are already installed. In practice, the containerized setup is the easiest way to expose it as a local service. The Perl/Mojolicious wrapper is configured for HTTPS when run with `hypnotoad`, while the Python/FastAPI wrapper is typically served over plain HTTP in local `uvicorn` examples unless TLS is added explicitly or terminated upstream.

See:

- [Download & Installation](download-and-installation.md)
- [Containerized installation](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/docker/README.md)
