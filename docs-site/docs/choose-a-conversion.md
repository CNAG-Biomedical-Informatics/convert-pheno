---
id: conversion-recipes
title: Choose a Conversion
sidebar_label: Choose a Conversion
slug: /conversion-recipes
---

Choose your **input format** first. Each recipe shows the required source
options and one complete command. The output can then be changed with the
shared output forms below.

For accepted files and format-specific behavior, see
[Supported Formats](supported-formats). For every implemented route, tested
inputs and reference outputs are available in the repository's
[`t/` fixture guide](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/tree/main/t).

<a id="choose-by-input-format"></a>

## Find Your Input

| Input | Main outputs | Required setup |
| --- | --- | --- |
| [Beacon v2 / BFF](#bff-input-examples) | PXF, OMOP-CDM | Beacon `individuals` JSON or YAML |
| [cBioPortal](#cbioportal-input-bff-output) | BFF, PXF, OMOP-CDM | Unpacked study directory or ZIP archive |
| [CDISC-ODM](#cdisc-odm-input-bff-output) | BFF, PXF, OMOP-CDM | Mapping file; REDCap dictionary only for REDCap-origin ODM |
| [CSV](#csv-input-bff-output) | BFF, PXF, OMOP-CDM | Mapping file |
| [CDISC Dataset-JSON](#dataset-json-input-bff-output) | BFF, PXF, OMOP-CDM | SDTM domain files including `DM` |
| [CDISC Dataset-XML](#dataset-xml-input-bff-output) | BFF, PXF, OMOP-CDM | SDTM domain files and Define-XML |
| [FHIR R4 / mCODE](#fhir-r4-input-bff-output) | BFF, PXF, OMOP-CDM | One or more JSON Bundles |
| [OMOP-CDM](#omop-cdm-input-bff-output) | BFF, PXF | CSV tables or SQL dump |
| [OpenClinica ODM](#openclinica-odm-input) | BFF, PXF, OMOP-CDM | Mapping file; metadata embedded in Snapshot ODM |
| [openEHR](#openehr-input-bff-output) | BFF, PXF | Canonical JSON or YAML compositions |
| [Phenopackets v2 / PXF](#pxf-input-bff-output) | BFF, OMOP-CDM | Phenopacket JSON or YAML |
| [REDCap](#redcap-input-bff-output) | BFF, PXF, OMOP-CDM | Data export, dictionary, and mapping file |

## Select the Output

The recipes use BFF output unless BFF is the input. Replace the final output
line with the form you need:

| Output | Command ending |
| --- | --- |
| BFF `individuals` | `-obff individuals.json` |
| Multiple BFF entities | `-obff --entities individuals biosamples datasets cohorts --out-dir bff_out/` |
| Phenopackets v2 | `-opxf phenopackets.json` |
| OMOP-CDM tables | `-oomop --out-dir omop_out/ --ohdsi-db` |

OMOP output requires the Athena-OHDSI database. Multi-entity BFF output writes
the requested entities for which the source provides or supports data. See
the [Command-Line Interface](use-as-a-command-line-interface) for naming and
`--out-dir` behavior.

<a id="before-you-run"></a>

Before using project data, install the tool through
[Download & Installation](download-and-installation) and run a small fixture
for the selected route. The [Command-Line Interface](use-as-a-command-line-interface)
documents all options.

<a id="command-examples"></a>

## Model Inputs

<a id="pxf-input-omop-cdm-output"></a>

### Phenopackets v2 / PXF {#pxf-input-bff-output}

```bash
convert-pheno \
  -ipxf phenopacket.json \
  -obff individuals.json
```

Use the multi-entity BFF ending when the Phenopacket contains biosamples that
should be written as Beacon `biosamples`. Details:
[Phenopackets v2](pxf) and [PXF to BFF mapping](pxf2bff).

<a id="bff-input-pxf-output"></a>
<a id="bff-input-omop-cdm-output"></a>

### Beacon v2 / BFF {#bff-input-examples}

```bash
convert-pheno \
  -ibff individuals.json \
  -opxf phenopackets.json
```

For OMOP-CDM, use the OMOP output ending above. Details:
[Beacon v2 Models](bff), [BFF to PXF mapping](bff2pxf), and
[BFF to OMOP mapping](bff2omop).

<a id="omop-cdm-input-pxf-output"></a>

### OMOP-CDM {#omop-cdm-input-bff-output}

```bash
convert-pheno \
  -iomop PERSON.csv CONCEPT.csv CONDITION_OCCURRENCE.csv \
  -obff individuals.json
```

Include `SPECIMEN.csv` and select `biosamples` for specimen-derived BFF
output. For large SQL dumps, add `--stream`; add `--ohdsi-db` when concept
lookup needs the Athena-OHDSI database. Details:
[OMOP-CDM](omop-cdm) and [OMOP to BFF mapping](omop2bff).

## Mapping-File Inputs {#mapping-file-input-examples}

These routes use a project mapping to turn source fields into BFF terms. The
same mapped records can be written directly as BFF, PXF, or OMOP-CDM.

<a id="csv-input-pxf-output"></a>
<a id="csv-input-omop-cdm-output"></a>

### CSV {#csv-input-bff-output}

```bash
convert-pheno \
  -icsv clinical.csv \
  --mapping-file mapping.yaml \
  --term-audit terminology.tsv \
  -obff individuals.json
```

Use `--sep` when the delimiter differs from the configured default. Details:
[CSV](csv), [Mapping Files](mapping-files), and [Terminology Search](terminology-search).

<a id="redcap-input-pxf-output"></a>
<a id="redcap-input-omop-cdm-output"></a>

### REDCap {#redcap-input-bff-output}

```bash
convert-pheno \
  -iredcap redcap.csv \
  --redcap-dictionary redcap-dictionary.csv \
  --mapping-file mapping.yaml \
  --term-audit terminology.tsv \
  -obff individuals.json
```

Details: [REDCap](redcap) and [Mapping Files](mapping-files).

<a id="cdisc-odm-input-pxf-output"></a>
<a id="cdisc-odm-input-omop-cdm-output"></a>

### CDISC-ODM {#cdisc-odm-input-bff-output}

```bash
convert-pheno \
  -icdisc-odm study.xml \
  --mapping-file odm-mapping.yaml \
  -obff individuals.json
```

For REDCap-origin ODM, reuse the REDCap mapping profile and add
`--redcap-dictionary dictionary.csv`. Details: [CDISC-ODM](cdisc-odm).

### OpenClinica ODM {#openclinica-odm-input}

```bash
convert-pheno \
  -icdisc-odm openclinica-export.xml \
  --mapping-file openclinica-mapping.yaml \
  -obff individuals.json
```

OpenClinica Snapshot ODM uses the CDISC-ODM route, but resolves field metadata
from the XML rather than a REDCap dictionary. Details:
[OpenClinica ODM](openclinica).

## Structured Clinical Inputs

<a id="cbioportal-input-pxf-output"></a>
<a id="cbioportal-input-omop-cdm-output"></a>

### cBioPortal {#cbioportal-input-bff-output}

```bash
convert-pheno \
  -icbioportal study/ \
  -obff --entities individuals biosamples datasets cohorts \
  --out-dir bff_out/
```

Clinical files are discovered through their meta descriptors. A mapping file
is optional. Details: [cBioPortal](cbioportal) and
[cBioPortal to BFF mapping](cbioportal2bff).

<a id="dataset-json-input-examples"></a>
<a id="dataset-json-input-pxf-output"></a>
<a id="dataset-json-input-omop-cdm-output"></a>

### CDISC Dataset-JSON {#dataset-json-input-bff-output}

```bash
convert-pheno \
  -idataset-json dm.json mh.json ae.json lb.json \
  -obff individuals.json
```

Supply one SDTM domain per file; `DM` is required. All supplied domains are
currently loaded and grouped by `USUBJID` in memory. Add
`--mapping-file sdtm-terminology.yaml` and `--term-audit terminology.tsv`
when the data owner has reviewed terminology rules. Details:
[CDISC Dataset-JSON](dataset-json) and
[Dataset-JSON to BFF mapping](datasetjson2bff).

<a id="dataset-xml-input-examples"></a>
<a id="dataset-xml-input-pxf-output"></a>
<a id="dataset-xml-input-omop-cdm-output"></a>

### CDISC Dataset-XML {#dataset-xml-input-bff-output}

```bash
convert-pheno \
  -idataset-xml dm.xml mh.xml ae.xml lb.xml \
  --define-xml define.xml \
  -obff individuals.json
```

Define-XML resolves domain and column metadata before rows are grouped by
participant in memory. Supported NCI identifiers in Define-XML are resolved
automatically; an optional `source.profile: sdtm` mapping can handle additional
reviewed terms. Details: [CDISC Dataset-XML](dataset-xml) and
[Dataset-XML to BFF mapping](datasetxml2bff).

<a id="fhir-r4-input-examples"></a>
<a id="fhir-r4-input-pxf-output"></a>
<a id="fhir-r4-input-omop-cdm-output"></a>

### FHIR R4 and mCODE {#fhir-r4-input-bff-output}

```bash
convert-pheno \
  -ifhir bundle.json \
  -obff individuals.json
```

Generic R4 and mCODE 4.0 use the same command; profile URLs are detected
automatically. Select multi-entity output for Specimen-derived `biosamples`.
Details: [FHIR R4](fhir) and [FHIR to BFF mapping](fhir2bff).

<a id="openehr-input-examples"></a>
<a id="openehr-input-pxf-output"></a>

### openEHR {#openehr-input-bff-output}

```bash
convert-pheno \
  -iopenehr patient-set.json \
  -obff individuals.json
```

Multiple canonical JSON or YAML compositions can be supplied and are grouped
by resolved patient identity. Details: [openEHR](openehr) and
[openEHR to BFF mapping](openehr2bff).

## Useful Additions

| Need | Option |
| --- | --- |
| Stable output for fixture comparison | `--test` |
| Terminology decision review | `--term-audit terminology.tsv` |
| Smaller BFF without copied source columns | `--no-source-info` |
| Separate Beacon entity files | `--entities ... --out-dir bff_out/` |
| Incremental OMOP SQL processing | `--stream` with `-iomop ... -obff` |

## Inspection Outputs

BFF and PXF input can also be flattened for inspection and downstream tools:

```bash
convert-pheno -ibff individuals.json -ocsv individuals.csv
convert-pheno -ibff individuals.json -ojsonf individuals.flattened.json
convert-pheno -ibff individuals.json -ojsonld individuals.jsonld
```

These outputs do not replace schema-aware BFF, PXF, or OMOP-CDM output.

## Search Mode for Mapping Files

The default `exact` search is appropriate when source labels match ontology
database labels. Use `mixed` when they differ:

```bash
convert-pheno \
  -icsv clinical.csv \
  --mapping-file mapping.yaml \
  --search mixed \
  --min-text-similarity-score 0.8 \
  --term-audit terminology.tsv \
  -obff individuals.json
```

See [Terminology Search](terminology-search) for resolution precedence, scoring, and audit-column interpretation.
