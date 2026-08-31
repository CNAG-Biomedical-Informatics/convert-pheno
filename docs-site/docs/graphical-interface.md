---
id: graphical-interface
title: Workbench
slug: /graphical-interface
---

The Convert-Pheno workbench is a **local browser application** for interactive
conversions. It automatically discovers the conversions
available on your installation and prepares each result as a downloadable
artifact.

:::info[Version availability]
The Workbench is available from **Convert-Pheno 0.35**.
:::

:::note[Current interface]
This is the **current workbench**. The [original Convert-Pheno Web App](https://convert-pheno.cnag.cat/)
is a **legacy demonstration** and does not reflect current conversion support.
:::

[![Convert-Pheno conversion workbench](/img/workbench-conversion.png)](/img/workbench-conversion.png)

*The workbench presents route selection, required input, output settings, and conversion as one workflow.*

## Run from Docker

Start the Workbench from the published Docker image:

```bash
docker run --rm \
  --publish 127.0.0.1:8080:8080 \
  manuelrueda/convert-pheno:latest
```

Open [http://127.0.0.1:8080](http://127.0.0.1:8080) in your browser. Keep the
terminal running while you use the Workbench; press `Ctrl+C` to stop it.

This command makes the Workbench available **only from your computer**. It has
no authentication and should not be exposed as a remote multi-user service.

OMOP output needs the separately distributed `ohdsi.db`. Mount it at the
standard database bundle location:

```bash
docker run --rm \
  --publish 127.0.0.1:8080:8080 \
  --volume "$PWD/ohdsi.db:/usr/share/convert-pheno/share/db/v0/ohdsi.db:ro" \
  manuelrueda/convert-pheno:latest
```

Routes that need this database remain in the route chooser when it is missing,
but are disabled with an explanation.

## Run from a source checkout

Development uses two processes. Start Mojolicious from the repository root:

```bash
morbo -l http://127.0.0.1:3000 api/perl/main.pl
```

Then start Vite in another terminal:

```bash
cd app
npm ci
npm run dev
```

Open [http://127.0.0.1:5173](http://127.0.0.1:5173). Vite proxies `/api` to Mojolicious. Node.js 24 is
required for the frontend toolchain; it is not required in the runtime Docker
image.

## Privacy and scope

JSON input and output stay in browser and API process memory. Uploaded files are
copied to a private per-request temporary directory and removed after success or
failure. The workbench does not use local storage, analytics, arbitrary server
paths, or payload logging. Changing a route or input clears stale results.

The workbench accepts JSON for Beacon v2, Phenopacket v2, FHIR, openEHR, and
OMOP, plus role-based uploads for OMOP table files or ZIP packages, CSV, REDCap, CDISC-ODM,
Dataset-JSON, Dataset-XML, cBioPortal study packages, and i2b2, PCORnet, or
Sentinel table packages. Each source has a
synthetic example drawn from the regression fixtures. Upload requests are
limited to **100 MiB** and run synchronously. Use the [command-line interface](use-as-a-command-line-interface)
for streaming or larger datasets.

## Terminology review

For mapping-based routes, the workbench enables a **color-coded XLSX terminology
report** by default. After conversion it shows complete counts for terms that can
be kept, similarity matches requiring review, unresolved terms, and source
fallbacks. The table starts with actionable decisions and can be filtered by
text, ontology, or review action.

[![Convert-Pheno terminology review](/img/workbench-terminology-review.png)](/img/workbench-terminology-review.png)

*Terminology decisions can be filtered in the browser and downloaded as a complete XLSX or TSV report.*

The browser keeps only a bounded preview while the downloadable XLSX or TSV
retains every decision. Review recommendations come directly from the Perl
audit writer; the interface does not recalculate terminology decisions. See
[Terminology Search](terminology-search) for the decision fields and review
workflow.
