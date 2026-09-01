# Convert-Pheno API (Perl)

This Mojolicious server powers the local Convert-Pheno Workbench. It uses the
same conversion code as the CLI and Perl module. Use this API for new HTTP(s)
integrations.

## Run locally

From the repository root:

```bash
morbo -l http://127.0.0.1:3000 api/perl/main.pl
```

For frontend development, run `npm run dev` from `app/` in a second terminal.
After `npm run build`, Mojolicious serves the built Workbench at `/`.

## Endpoints

- `GET /api/health`
- `GET /api/conversions`
- `POST /api/conversions/{conversion}`
- `GET /examples/{source}` for the synthetic examples bundled with the Workbench

Example:

```bash
curl -H 'Content-Type: application/json' \
  -d '{"input":{"data":{"phenopacket":{"id":"P1"}}},"output":{"entities":["individuals"]},"options":{}}' \
  http://127.0.0.1:3000/api/conversions/pxf2bff
```

For conversions that need files, send a `multipart/form-data` request. The
`request` part holds the output settings and options as JSON. Send each input
file under the role shown by `GET /api/conversions`, such as `source` or
`mapping`:

```bash
curl --fail-with-body \
  --form 'request={"output":{"entities":["individuals"]},"options":{"separator":","}}' \
  --form source=@records.csv \
  --form mapping=@mapping.yaml \
  http://127.0.0.1:3000/api/conversions/csv2bff
```

For built-in routes such as OMOP-to-BFF, `mapping` is optional and supplies
only dataset and cohort metadata. The structural source-to-BFF mapping remains
built in.

## Request limits

Each request can upload up to 100 MiB. Uploaded files are deleted after the
request finishes. The API does not accept paths to files already on the server.
Use the CLI or module for streaming and larger inputs.

## Terminology reports

For conversions that search terminology databases, set `term_audit` to `xlsx`
or `tsv`. The response includes the complete report. It also includes summary
counts and a short preview in `meta.terminologyAudit`, which the Workbench uses
for its review screen.

## Responses

Successful responses contain `warnings` and `artifacts`. Each item in
`artifacts` is one generated output file and includes its filename, file type,
encoding, and content.

Errors use these HTTP status codes:

- `404`: unknown conversion
- `422`: invalid request or conversion failure
- `503`: a required database or other resource is unavailable
- `500`: the server encountered an unexpected error

Both JSON and multipart requests are supported. See
[openapi.json](./openapi.json) for the complete request and response contract.
