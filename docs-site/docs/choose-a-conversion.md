---
id: conversion-recipes
title: Choose a Conversion
sidebar_label: Choose a Conversion
slug: /conversion-recipes
---

This page is the quickest way to choose a conversion route. Start with your **input format**, then pick the output you need and copy the matching command.

:::tip[Most users]
Use the command-line interface for real files, mapping files, REDCap dictionaries, OMOP tables, audit TSV files, and multi-entity BFF output.
:::

For a compact list of accepted inputs and outputs, see [Supported Formats](supported-formats). Route-specific setup details remain on the linked format pages. Small inputs and reference outputs for every implemented route are indexed in the repository's [`t/` fixture guide](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/tree/main/t).

## Choose by Input Format

### Phenopackets v2 / PXF Input

| Target output | Route | Notes |
| --- | --- | --- |
| Beacon v2 / `BFF` | [`pxf2bff`](#pxf-input-bff-output) | Supports `individuals`; can also emit `biosamples`, `datasets`, and `cohorts` with `--entities` |
| OMOP-CDM CSV | [`pxf2omop`](#pxf-input-omop-cdm-output) | Writes OMOP tables to `--out-dir` |
| Inspection output | [Additional outputs](#inspection-outputs) | Flattened JSON, CSV, JSON-LD, YAML-LD |

### Beacon v2 / BFF Input

| Target output | Route | Notes |
| --- | --- | --- |
| Phenopackets v2 / `PXF` | [`bff2pxf`](#bff-input-pxf-output) | Input is Beacon `individuals` JSON/YAML |
| OMOP-CDM CSV | [`bff2omop`](#bff-input-omop-cdm-output) | Writes OMOP tables to `--out-dir` |
| Inspection output | [Additional outputs](#inspection-outputs) | Flattened JSON, CSV, JSON-LD, YAML-LD |

### OMOP-CDM Input

| Target output | Route | Notes |
| --- | --- | --- |
| Beacon v2 / `BFF` | [`omop2bff`](#omop-cdm-input-bff-output) | Use `--ohdsi-db` when concept lookup against Athena-OHDSI is needed |
| Phenopackets v2 / `PXF` | [`omop2pxf`](#omop-cdm-input-pxf-output) | Internally goes through BFF |

### REDCap Input

| Target output | Route | Notes |
| --- | --- | --- |
| Beacon v2 / `BFF` | [`redcap2bff`](#redcap-input-bff-output) | Requires `--mapping-file` and usually `--redcap-dictionary` |
| Phenopackets v2 / `PXF` | [`redcap2pxf`](#redcap-input-pxf-output) | Uses the same mapping model as `redcap2bff` |
| OMOP-CDM CSV | [`redcap2omop`](#redcap-input-omop-cdm-output) | Goes through BFF; requires `--ohdsi-db` |

### CSV Input

| Target output | Route | Notes |
| --- | --- | --- |
| Beacon v2 / `BFF` | [`csv2bff`](#csv-input-bff-output) | Requires `--mapping-file` |
| Phenopackets v2 / `PXF` | [`csv2pxf`](#csv-input-pxf-output) | Requires `--mapping-file` |
| OMOP-CDM CSV | [`csv2omop`](#csv-input-omop-cdm-output) | Goes through BFF; requires `--ohdsi-db` |

### CDISC-ODM Input

| Target output | Route | Notes |
| --- | --- | --- |
| Beacon v2 / `BFF` | [`cdiscodm2bff`](#cdisc-odm-input-bff-output) | Requires `--mapping-file`; `--redcap-dictionary` only for REDCap-origin ODM |
| Phenopackets v2 / `PXF` | [`cdiscodm2pxf`](#cdisc-odm-input-pxf-output) | Uses the same detected ODM profile and mapping context |
| OMOP-CDM CSV | [`cdiscodm2omop`](#cdisc-odm-input-omop-cdm-output) | Goes through BFF; requires `--ohdsi-db` |

### CDISC Dataset-JSON Input

| Target output | Route | Notes |
| --- | --- | --- |
| Beacon v2 / `BFF` | [`datasetjson2bff`](#dataset-json-input-bff-output) | SDTM domains are grouped by `USUBJID`; no mapping file |
| Phenopackets v2 / `PXF` | [`datasetjson2pxf`](#dataset-json-input-pxf-output) | Internally goes through BFF |
| OMOP-CDM CSV | [`datasetjson2omop`](#dataset-json-input-omop-cdm-output) | Internally goes through BFF; requires `--ohdsi-db` |

### FHIR R4 Input

| Target output | Route | Notes |
| --- | --- | --- |
| Beacon v2 / `BFF` | [`fhir2bff`](#fhir-r4-input-bff-output) | Bundle resources are grouped by Patient; can emit biosamples from Specimen |
| Phenopackets v2 / `PXF` | [`fhir2pxf`](#fhir-r4-input-pxf-output) | Internally goes through BFF and preserves biosamples |
| OMOP-CDM CSV | [`fhir2omop`](#fhir-r4-input-omop-cdm-output) | Internally goes through BFF; requires `--ohdsi-db` |

### openEHR Input

| Target output | Route | Notes |
| --- | --- | --- |
| Beacon v2 / `BFF` | [`openehr2bff`](#openehr-input-bff-output) | Canonical JSON or YAML compositions become Beacon `individuals` |
| Phenopackets v2 / `PXF` | [`openehr2pxf`](#openehr-input-pxf-output) | Internally goes through BFF |

## Before You Run

- Install the tool first: [Download & Installation](download-and-installation).
- Use `--test` when comparing example outputs because it removes time-changing metadata.
- Use `--search-audit-tsv FILE` for mapping-file conversions if you want to inspect ontology lookup results.
- Use `--no-source-info` only when you want smaller BFF output and do not need copied source columns under `info`.
- Use `--entities` only with `-obff` and `--out-dir` when writing multiple Beacon entity files.
- Start with a regression fixture when evaluating a route; this separates installation problems from project-specific input or mapping issues.

## Command Examples

### PXF Input: BFF Output

Individuals-only BFF output:

```bash
convert-pheno -ipxf phenopacket.json -obff individuals.json
```

Entity-aware BFF output:

```bash
convert-pheno -ipxf phenopacket.json -obff \
  --entities individuals biosamples datasets cohorts \
  --out-dir bff_out/
```

Use this when your Phenopacket contains biosample data and you want first-class Beacon `biosamples` output instead of keeping biosample content under `individuals.info`.

More detail: [Phenopackets v2](pxf), [PXF to BFF mapping](pxf2bff).

### PXF Input: OMOP-CDM Output

```bash
convert-pheno -ipxf phenopacket.json -oomop --out-dir omop_out/
```

More detail: [OMOP-CDM](omop-cdm).

## BFF Input Examples

### BFF Input: PXF Output

```bash
convert-pheno -ibff individuals.json -opxf phenopacket.json
```

Set the fallback Phenopackets vital status when no source value is available:

```bash
convert-pheno -ibff individuals.json -opxf phenopacket.json \
  --default-vital-status UNKNOWN_STATUS
```

More detail: [Beacon v2 Models](bff), [BFF to PXF mapping](bff2pxf).

### BFF Input: OMOP-CDM Output

```bash
convert-pheno -ibff individuals.json -oomop --out-dir omop_out/
```

More detail: [BFF to OMOP mapping](bff2omop).

## OMOP-CDM Input Examples

### OMOP-CDM Input: BFF Output

Individuals-only BFF output from OMOP CSV tables:

```bash
convert-pheno -iomop PERSON.csv CONCEPT.csv CONDITION_OCCURRENCE.csv \
  -obff individuals.json
```

Biosamples output from OMOP `SPECIMEN`:

```bash
convert-pheno -iomop PERSON.csv CONCEPT.csv SPECIMEN.csv \
  -obff --entities biosamples --out-dir bff_out/
```

Large OMOP SQL dump with OHDSI lookup:

```bash
convert-pheno -iomop dump.sql.gz -obff individuals.json.gz \
  --stream --ohdsi-db
```

Smaller BFF output without copied OMOP source columns:

```bash
convert-pheno -iomop dump.sql.gz -obff individuals.json.gz \
  --stream --ohdsi-db --no-source-info
```

More detail: [OMOP-CDM](omop-cdm), [OMOP to BFF mapping](omop2bff).

### OMOP-CDM Input: PXF Output

```bash
convert-pheno -iomop dump.sql.gz -opxf phenopackets.json \
  --stream --ohdsi-db
```

This route internally maps OMOP data to BFF before writing Phenopackets.

## Mapping-File Input Examples

Mapping-file routes are for project-specific tabular data where source columns need to be mapped to Beacon terms. This includes `CSV`, `REDCap`, and `CDISC-ODM`.

### CSV Input: BFF Output

```bash
convert-pheno -icsv clinical.csv \
  --mapping-file mapping.yaml \
  --search-audit-tsv search-audit.tsv \
  -obff individuals.json
```

Multi-entity BFF output with mapping-file metadata for datasets and cohorts:

```bash
convert-pheno -icsv clinical.csv \
  --mapping-file mapping.yaml \
  --search-audit-tsv search-audit.tsv \
  -obff --entities individuals datasets cohorts \
  --out-dir bff_out/
```

More detail: [CSV](csv), [mapping file](tbl/mapping-file), [DB search](tbl/db-search).

### CSV Input: PXF Output

```bash
convert-pheno -icsv clinical.csv \
  --mapping-file mapping.yaml \
  -opxf phenopackets.json
```

### CSV Input: OMOP-CDM Output

```bash
convert-pheno -icsv clinical.csv \
  --mapping-file mapping.yaml \
  --sep , \
  -oomop --out-dir omop_out/ \
  --ohdsi-db
```

This is a single CLI route, but internally the mapped CSV records are normalized to BFF before the supported OMOP tables are written. More detail: [CSV](csv), [BFF to OMOP mapping](bff2omop).

### REDCap Input: BFF Output

```bash
convert-pheno -iredcap redcap.csv \
  --redcap-dictionary redcap-dictionary.csv \
  --mapping-file mapping.yaml \
  --search-audit-tsv search-audit.tsv \
  -obff individuals.json
```

More detail: [REDCap](redcap), [Working with Mapping Files](mapping-files).

### REDCap Input: PXF Output

```bash
convert-pheno -iredcap redcap.csv \
  --redcap-dictionary redcap-dictionary.csv \
  --mapping-file mapping.yaml \
  -opxf phenopackets.json
```

### REDCap Input: OMOP-CDM Output

```bash
convert-pheno -iredcap redcap.csv \
  --redcap-dictionary redcap-dictionary.csv \
  --mapping-file mapping.yaml \
  -oomop --out-dir omop_out/ \
  --ohdsi-db
```

### CDISC-ODM Input: BFF Output

```bash
convert-pheno -icdisc-odm study.xml \
  --mapping-file odm-mapping.yaml \
  -obff individuals.json
```

This form uses embedded ODM metadata and a mapping declaring
`source.profile: cdisc-odm`. For a REDCap ODM export, reuse the REDCap mapping
and add `--redcap-dictionary dictionary.csv`; that mapping declares
`source.profile: redcap`. More detail: [CDISC-ODM](cdisc-odm).

### CDISC-ODM Input: PXF Output

```bash
convert-pheno -icdisc-odm study.xml \
  --mapping-file odm-mapping.yaml \
  -opxf phenopackets.json
```

### CDISC-ODM Input: OMOP-CDM Output

```bash
convert-pheno -icdisc-odm study.xml \
  --mapping-file odm-mapping.yaml \
  -oomop --out-dir omop_out/ \
  --ohdsi-db
```

## Dataset-JSON Input Examples

Dataset-JSON input accepts one SDTM domain document per file. `DM` is required;
additional mapped or provenance-only domains can be supplied in the same
command.

### Dataset-JSON Input: BFF Output

```bash
convert-pheno -idataset-json dm.json mh.json ae.json lb.json \
  -obff individuals.json
```

Entity-aware output can also synthesize dataset and cohort metadata from
`studyOID` and the `TS` title:

```bash
convert-pheno -idataset-json dm.json mh.json ts.json \
  -obff --entities individuals datasets cohorts \
  --out-dir bff_out/
```

More detail: [CDISC Dataset-JSON](dataset-json),
[Dataset-JSON to BFF mapping](datasetjson2bff).

### Dataset-JSON Input: PXF Output

```bash
convert-pheno -idataset-json dm.json mh.json ae.json lb.json \
  -opxf phenopackets.json
```

### Dataset-JSON Input: OMOP-CDM Output

```bash
convert-pheno -idataset-json dm.json mh.json ae.json lb.json \
  -oomop --out-dir omop_out/ \
  --ohdsi-db
```

All supplied Dataset-JSON domains are currently loaded and grouped in memory.

## FHIR R4 Input Examples

FHIR input accepts one or more R4 JSON Bundle files and groups associated
resources by Patient. A mapping file is not required.

### FHIR R4 Input: BFF Output

```bash
convert-pheno -ifhir bundle.json -obff individuals.json
```

To write Specimen-derived biosamples and collection metadata as separate BFF
entities:

```bash
convert-pheno -ifhir bundle.json \
  -obff --entities individuals biosamples datasets cohorts \
  --out-dir bff_out/
```

More detail: [FHIR R4](fhir), [FHIR to BFF mapping](fhir2bff).

### FHIR R4 Input: PXF Output

```bash
convert-pheno -ifhir bundle.json -opxf phenopackets.json
```

### FHIR R4 Input: OMOP-CDM Output

```bash
convert-pheno -ifhir bundle.json \
  -oomop --out-dir omop_out/ \
  --ohdsi-db
```

Use `--no-source-info` when raw FHIR resources should not be copied into BFF
provenance. All supplied Bundles and grouped Patient records are currently held
in memory.

## openEHR Input Examples

### openEHR Input: BFF Output

```bash
convert-pheno -iopenehr patient-set.json -obff individuals.json
```

### openEHR Input: PXF Output

```bash
convert-pheno -iopenehr demographics.json ips.json laboratory.json \
  -opxf phenopackets.json
```

Multiple files are grouped by resolved patient identity before conversion.
More detail: [openEHR](openehr), [openEHR to BFF mapping](openehr2bff).

## Inspection Outputs

For BFF or PXF input, Convert-Pheno can also write inspection-oriented outputs:

```bash
convert-pheno -ibff individuals.json -ocsv individuals.csv
convert-pheno -ibff individuals.json -ojsonf individuals.flattened.json
convert-pheno -ibff individuals.json -ojsonld individuals.jsonld
```

These are useful for review and downstream tooling, but they are not replacements for schema-aware `BFF`, `PXF`, or `OMOP-CDM` output.

## Search Mode for Mapping Files

Use `exact` unless your mapping file contains labels that differ from ontology database labels.

```bash
convert-pheno -icsv clinical.csv \
  --mapping-file mapping.yaml \
  --search mixed \
  --min-text-similarity-score 0.8 \
  --search-audit-tsv search-audit.tsv \
  -obff individuals.json
```

For interpretation of ontology lookup results, see [DB Search](tbl/db-search).
