---
id: conversion-recipes
title: Choose a Conversion
sidebar_label: Choose a Conversion
slug: /conversion-recipes
---

Choose your **input format** first. The table identifies the available main
outputs and any extra files required. Continue to the corresponding command,
then use the linked format guide for input details and route-specific options.

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

The examples use BFF output unless BFF is the input. Replace the final output
line when another target is needed:

| Output | Command ending |
| --- | --- |
| BFF `individuals` | `-obff individuals.json` |
| Multiple BFF entities | `-obff --entities individuals biosamples datasets cohorts --out-dir bff_out/` |
| Phenopackets v2 | `-opxf phenopackets.json` |
| OMOP-CDM tables | `-oomop --out-dir omop_out/ --ohdsi-db` |

OMOP output requires the Athena-OHDSI database. Multi-entity BFF output writes
the requested entities supported by the source.

<a id="before-you-run"></a>

:::tip[Before using project data]
Complete [installation](download-and-installation), run one small example, and
review the guide for your input format. The [CLI reference](use-as-a-command-line-interface)
documents shared options and output naming.
:::

<a id="command-examples"></a>

## Model Inputs

<a id="pxf-input-omop-cdm-output"></a>

### Phenopackets v2 / PXF {#pxf-input-bff-output}

```bash
convert-pheno \
  -ipxf phenopacket.json \
  -obff individuals.json
```

Use entity-aware BFF output when Phenopacket biosamples should be written as
Beacon `biosamples`. See [Phenopackets v2](pxf).

<a id="bff-input-pxf-output"></a>
<a id="bff-input-omop-cdm-output"></a>

### Beacon v2 / BFF {#bff-input-examples}

```bash
convert-pheno \
  -ibff individuals.json \
  -opxf phenopackets.json
```

For OMOP-CDM, use the OMOP output ending above. See [Beacon v2 Models](bff).

<a id="omop-cdm-input-pxf-output"></a>

### OMOP-CDM {#omop-cdm-input-bff-output}

```bash
convert-pheno \
  -iomop PERSON.csv CONCEPT.csv CONDITION_OCCURRENCE.csv \
  -obff individuals.json
```

Add the clinical tables needed by the conversion; include `SPECIMEN.csv` for
biosamples. See [OMOP-CDM](omop-cdm).

## Mapping-File Inputs {#mapping-file-input-examples}

These routes use a project mapping to turn source fields into BFF terms. The
same records can be written as BFF, PXF, or OMOP-CDM.

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

See [CSV](csv) and [Mapping Files](mapping-files).

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

See [REDCap](redcap) and [Mapping Files](mapping-files).

<a id="cdisc-odm-input-pxf-output"></a>
<a id="cdisc-odm-input-omop-cdm-output"></a>

### CDISC-ODM {#cdisc-odm-input-bff-output}

```bash
convert-pheno \
  -icdisc-odm study.xml \
  --mapping-file odm-mapping.yaml \
  -obff individuals.json
```

REDCap-origin ODM also uses its REDCap dictionary. See [CDISC-ODM](cdisc-odm).

### OpenClinica ODM {#openclinica-odm-input}

```bash
convert-pheno \
  -icdisc-odm openclinica-export.xml \
  --mapping-file openclinica-mapping.yaml \
  -obff individuals.json
```

OpenClinica Snapshot ODM resolves metadata from the XML. See
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

See [cBioPortal](cbioportal).

<a id="dataset-json-input-examples"></a>
<a id="dataset-json-input-pxf-output"></a>
<a id="dataset-json-input-omop-cdm-output"></a>

### CDISC Dataset-JSON {#dataset-json-input-bff-output}

```bash
convert-pheno \
  -idataset-json dm.json mh.json ae.json lb.json \
  -obff individuals.json
```

Exactly one `DM` domain is required. See [Dataset-JSON](dataset-json).

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

Dataset-XML requires Define-XML and exactly one `DM` domain. See
[Dataset-XML](dataset-xml).

<a id="fhir-r4-input-examples"></a>
<a id="fhir-r4-input-pxf-output"></a>
<a id="fhir-r4-input-omop-cdm-output"></a>

### FHIR R4 and mCODE {#fhir-r4-input-bff-output}

```bash
convert-pheno \
  -ifhir bundle.json \
  -obff individuals.json
```

mCODE uses the same command and is detected from profile URLs. See
[FHIR R4 and mCODE](fhir).

<a id="openehr-input-examples"></a>
<a id="openehr-input-pxf-output"></a>

### openEHR {#openehr-input-bff-output}

```bash
convert-pheno \
  -iopenehr patient-set.json \
  -obff individuals.json
```

See [openEHR](openehr).

## Useful Options

| Need | Option |
| --- | --- |
| Terminology decision review | `--term-audit terminology.tsv` |
| Smaller BFF without copied source columns | `--no-source-info` |
| Separate Beacon entity files | `--entities ... --out-dir bff_out/` |
| Incremental OMOP processing | `--stream` with `-iomop ... -obff` |

## Inspection Outputs

<a id="inspection-outputs"></a>

BFF and PXF input can also be flattened for inspection and downstream tools:

```bash
convert-pheno -ibff individuals.json -ocsv individuals.csv
convert-pheno -ibff individuals.json -ojsonf individuals.flattened.json
convert-pheno -ibff individuals.json -ojsonld individuals.jsonld
```

For terminology search modes and audit interpretation, see
[Terminology Search](terminology-search).
