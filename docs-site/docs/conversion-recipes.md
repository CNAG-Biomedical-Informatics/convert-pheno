---
title: Conversion Recipes
sidebar_label: Conversion Recipes
---

<div className="convertDocHero">
  <p className="convertEyebrow">Recipes</p>
  <h2>Copy-paste commands for common conversion routes.</h2>
  <p>
    These examples are intentionally short. Replace file names and output
    directories with your own paths.
  </p>
  <div className="convertHeroActions">
    <a className="button button--primary" href="#pxf-to-bff">PXF to BFF</a>
    <a className="button button--secondary" href="#omop-cdm-to-bff">OMOP to BFF</a>
    <a className="button button--secondary" href="#mapping-file-conversions">Mapping files</a>
  </div>
</div>

:::tip[Start with stable output]
Use `--test` when comparing output files in tests or examples. It removes time-changing metadata.
:::

## PXF to BFF

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

## OMOP-CDM to BFF

Individuals-only output from OMOP CSV tables:

```bash
convert-pheno -iomop PERSON.csv CONCEPT.csv CONDITION_OCCURRENCE.csv \
  -obff individuals.json
```

Biosamples output from OMOP `SPECIMEN`:

```bash
convert-pheno -iomop PERSON.csv CONCEPT.csv SPECIMEN.csv \
  -obff --entities biosamples --out-dir bff_out/
```

Large OMOP dump with OHDSI lookup:

```bash
convert-pheno -iomop dump.sql.gz -obff individuals.json.gz \
  --stream --ohdsi-db
```

## Mapping-File Conversions

CSV to multi-entity BFF with ontology search audit:

```bash
convert-pheno -icsv clinical.csv \
  --mapping-file mapping.yaml \
  --search-audit-tsv search-audit.tsv \
  -obff --entities individuals datasets cohorts \
  --out-dir bff_out/
```

REDCap to BFF with data dictionary:

```bash
convert-pheno -iredcap redcap.csv \
  --redcap-dictionary redcap-dictionary.csv \
  --mapping-file mapping.yaml \
  --search-audit-tsv search-audit.tsv \
  -obff individuals.json
```

CDISC-ODM to BFF:

```bash
convert-pheno -icdisc study.xml \
  --mapping-file mapping.yaml \
  -obff individuals.json
```

## BFF to Other Formats

BFF to Phenopackets v2:

```bash
convert-pheno -ibff individuals.json -opxf phenopacket.json
```

BFF to OMOP-CDM CSV tables:

```bash
convert-pheno -ibff individuals.json -oomop --out-dir omop_out/
```

## Reduce Source Provenance

By default, BFF output keeps source values in `info` so users can audit and query original variables. For smaller exports, disable that payload:

```bash
convert-pheno -iomop PERSON.csv CONCEPT.csv CONDITION_OCCURRENCE.csv \
  -obff individuals.json \
  --no-source-info
```

## Search Mode

Use `exact` unless your mapping file contains labels that differ from the ontology database labels.

```bash
convert-pheno -icsv clinical.csv \
  --mapping-file mapping.yaml \
  --search mixed \
  --min-text-similarity-score 0.8 \
  --search-audit-tsv search-audit.tsv \
  -obff individuals.json
```

For interpretation of audit and validation output, see [Output Validation](output-validation).
