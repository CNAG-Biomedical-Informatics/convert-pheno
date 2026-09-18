# Convert-Pheno API (Mojolicious)

This local service powers Convert-Pheno Desktop and uses the same core engine
as the CLI. Use it for new HTTP(s) integrations. It does not serve a browser UI.

## Run locally

Desktop starts and authenticates its own service. For a standalone service,
set a private token of at least 32 characters, then start from the repository root:

```bash
export CONVERT_PHENO_API_TOKEN="$(openssl rand -hex 32)"
morbo -l http://127.0.0.1:3000 api/perl/main.pl
```

Send `Authorization: Bearer <token>` with every request. Keep the service on
loopback; do not publish its token or expose native file-access endpoints.

## Conversion workflow

1. Read `GET /api/conversions` for supported routes, options, and file roles
2. Upload files to `POST /api/inputs`, or supply JSON directly
3. Submit a request to `POST /api/jobs`
4. Poll `GET /api/jobs/{id}` until the job completes or fails
5. Preview or download the files listed in `data.result.artifacts`

For example, upload a Phenopacket from the repository:

```bash
curl --fail-with-body \
  -H "Authorization: Bearer $CONVERT_PHENO_API_TOKEN" \
  -F files=@t/pxf2bff/in/pxf.json \
  http://127.0.0.1:3000/api/inputs
```

Use its returned `data[0].id` as `HANDLE`:

```bash
curl --fail-with-body \
  -H "Authorization: Bearer $CONVERT_PHENO_API_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"conversion":"pxf2bff","input":{"files":{"source":["HANDLE"]}},"output":{"entities":["individuals"]},"options":{}}' \
  http://127.0.0.1:3000/api/jobs
```

The `202` response means **queued**, not successfully converted. Check
`data.status`; failures include `data.message`. Once completed, download
`GET /api/jobs/{id}/outputs/{artifact}/download`. Downloads contain the original
file bytes, not base64-wrapped JSON.

## Files, reports, and limits

Upload requests accept up to 128 files and 100 MiB total. Returned handles are
reusable within that service's state directory. Uploaded files are not removed
when the upload request finishes. Generic clients cannot submit filesystem paths;
the native app has separately authenticated endpoints for local file selection.

Map handles to roles such as `source`, `mapping`, or `dictionary` in the job
request. The catalog describes which roles each conversion accepts. Optional
metadata mappings and BFF-to-OMOP terminology mappings use that same mechanism.

Set `options.term_audit` to `xlsx` or `tsv` to request a terminology report.
Completed jobs include the report among their outputs and a bounded preview in
`data.result.meta.terminologyAudit`.

Runs execute one at a time by default. Read the saved limit with
`GET /api/jobs/settings`, or change it with `POST /api/jobs/settings` and
`{"maxConcurrentJobs": 4}`. The maximum is returned as `maxAllowedConcurrentJobs`.
Desktop detects available logical CPUs, capped at 16. Standalone services default
to a limit of one; operators can set `CONVERT_PHENO_JOB_LIMIT` (1–16) before
starting the service. The setting persists across service restarts.
Lowering it does not interrupt active jobs. Each job has its own worker process
and output folder; higher limits require more memory.
Cancel an individual run with `POST /api/jobs/{id}/cancel`.
Deleting history with `DELETE /api/jobs/{id}` keeps outputs; deleting
`/api/jobs/{id}/files` also removes the run's outputs, never original source files.

## Responses

Responses normally use `{ok, data}` or `{ok: false, error: {message, ...}}`.
Missing authentication returns `401`; rejected hosts, origins, or native access
return `403`; rejected job requests return `422`. A conversion that fails after
submission is reported through its job status, not the submission's HTTP status.

See [openapi.json](./openapi.json) for endpoints and request schemas.
