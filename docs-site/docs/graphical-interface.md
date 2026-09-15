---
id: graphical-interface
title: Desktop Application
slug: /graphical-interface
---

The Convert-Pheno desktop application provides a native interface for local,
interactive conversions. It uses the same Perl engine and public route registry
as the command-line interface.

## How it works

1. Choose the source and target formats. The application shows only supported
   routes and relevant options.
2. Select source files, mapping files, dictionaries, or table packages as
   required by that route. Synthetic examples are available for trying the
   workflow first.
3. Review the output location and start the conversion. Runs execute in a local
   queue, so the application remains responsive.
4. Inspect generated records or tables, review terminology decisions when an
   audit was requested, and open or export the output files.

The **Sources**, **Runs**, **Outputs**, **Terminology Review**, and **Compare**
views keep input selection, execution, and result inspection within one local
workspace. The application does not send participant data to a remote service.

:::info[Version availability]
The desktop application is available from **Convert-Pheno 0.35** for Linux,
macOS, and Windows.
:::

:::note[Current interface]
This is the **current graphical interface**. The [original Convert-Pheno Web App](https://convert-pheno.cnag.cat/)
is a **legacy demonstration** and does not reflect current conversion support.
:::

## Install

Platform installers are prepared for Linux x86_64 and ARM64, macOS Apple
Silicon and Intel, and Windows x86_64.

:::warning[Test packages]
The current GitHub pre-releases are unsigned compatibility builds. They are
provided to test installation and launch behavior on real computers, not as the
stable Convert-Pheno release. macOS may require explicit approval in Privacy &
Security, and Windows may show a SmartScreen warning.
:::

Open [Convert-Pheno releases](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/releases),
choose the latest desktop test build, and download the installer matching your
operating system and processor. The adjacent `.sha256` file records the checksum
produced after package inspection.

## Run from a source checkout

Install the frontend dependencies and let Tauri start the private local engine:

```bash
cd app
npm ci
npm run desktop
```

Node.js 24, Rust 1.86, Tauri's platform build libraries, Perl, and the normal
Convert-Pheno dependencies are required for source development. Packaged
applications include their own Perl runtime.

## Privacy and scope

The native file picker grants the private local engine access only to locations
selected by the user. Inputs remain unchanged. Run state and generated files are
stored under the operating system's application-data directory or in an output
folder selected by the user. Participant payloads are not logged or sent to an
external service.

The desktop application accepts JSON for Beacon v2, Phenopacket v2, FHIR, openEHR, and
OMOP, plus role-based uploads for OMOP table files or ZIP packages, CSV, REDCap, CDISC-ODM,
Dataset-JSON, Dataset-XML, cBioPortal study packages, and i2b2, PCORnet, or
Sentinel table packages. Entity-aware BFF routes also accept the optional
compact Mapping V2 metadata file advertised for that route. Each source has a
synthetic example drawn from the regression fixtures. Runs are queued locally,
so the interface remains responsive while the Perl worker performs a conversion.
Use the [command-line interface](use-as-a-command-line-interface) when scripting
or streaming is preferable.

## OHDSI terminology database

`ohdsi.db` is not included in the installers because it is approximately 3.2 GB.
Open **Resources**, download the current file from Google Drive, and select
**Install downloaded database**. The application verifies its declared size and
SHA-256 before making OHDSI-dependent routes available.

## Terminology review

For mapping-based routes, a **color-coded XLSX terminology report** can be
requested before starting the run. After conversion it counts exact or configured terms,
similarity matches, unresolved terms, and source fallbacks. Filter the preview
by text, ontology, or review action.

The application shows a grouped preview; the XLSX download contains every
decision. Review recommendations come from the Perl audit writer rather than
being recalculated in the interface. See [Terminology Search](terminology-search)
for the fields and suggested review order.
