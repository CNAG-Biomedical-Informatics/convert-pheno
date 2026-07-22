---
title: Choose a Conversion
sidebar_label: Choose a Conversion
---

This page is the quickest way to choose a conversion route. Start with your **input format**, then pick the output you need and copy the matching command.

:::tip[Most users]
Use the command-line interface for real files, mapping files, REDCap dictionaries, OMOP tables, audit TSV files, and multi-entity BFF output.
:::

For a compact list of accepted inputs and outputs, see [Supported Formats](supported-formats). Route-specific setup details remain on the linked format pages.

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

### CSV Input

| Target output | Route | Notes |
| --- | --- | --- |
| Beacon v2 / `BFF` | [`csv2bff`](#csv-input-bff-output) | Requires `--mapping-file` |
| Phenopackets v2 / `PXF` | [`csv2pxf`](#csv-input-pxf-output) | Requires `--mapping-file` |

### CDISC-ODM Input

| Target output | Route | Notes |
| --- | --- | --- |
| Beacon v2 / `BFF` | [`cdisc2bff`](#cdisc-odm-input-bff-output) | Requires `--mapping-file` |
| Phenopackets v2 / `PXF` | [`cdisc2pxf`](#cdisc-odm-input-pxf-output) | Requires `--mapping-file` |

## Before You Run

- Install the tool first: [Download & Installation](download-and-installation).
- Use `--test` when comparing example outputs because it removes time-changing metadata.
- Use `--search-audit-tsv FILE` for mapping-file conversions if you want to inspect ontology lookup results.
- Use `--no-source-info` only when you want smaller BFF output and do not need copied source columns under `info`.
- Use `--entities` only with `-obff` and `--out-dir` when writing multiple Beacon entity files.

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

More detail: [OMOP-CDM](omop-cdm), [OMOP to BFF mapping](omop2bff), [Output Validation](output-validation).

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

### REDCap Input: BFF Output

```bash
convert-pheno -iredcap redcap.csv \
  --redcap-dictionary redcap-dictionary.csv \
  --mapping-file mapping.yaml \
  --search-audit-tsv search-audit.tsv \
  -obff individuals.json
```

More detail: [REDCap](redcap), [Guided Examples](tutorial).

### REDCap Input: PXF Output

```bash
convert-pheno -iredcap redcap.csv \
  --redcap-dictionary redcap-dictionary.csv \
  --mapping-file mapping.yaml \
  -opxf phenopackets.json
```

### CDISC-ODM Input: BFF Output

```bash
convert-pheno -icdisc study.xml \
  --mapping-file mapping.yaml \
  -obff individuals.json
```

More detail: [CDISC-ODM](cdisc-odm).

### CDISC-ODM Input: PXF Output

```bash
convert-pheno -icdisc study.xml \
  --mapping-file mapping.yaml \
  -opxf phenopackets.json
```

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

For interpretation of audit and validation output, see [Output Validation](output-validation).
