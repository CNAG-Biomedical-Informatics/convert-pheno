---
title: Trust and Validation
sidebar_label: Trust & Validation
---

# Trust and Validation

Clinical conversion is easier to trust when users can inspect both the mapped output and the source values that produced it.

## Source Provenance in `info`

When Convert-Pheno creates BFF from `OMOP-CDM`, `CSV`, `REDCap`, or `CDISC-ODM`, it preserves raw source values in `info` by default.

This is deliberate:

- Users can cross-check converted records against the original input.
- Beacon-style APIs can still expose or query source-specific values.
- Conversion bugs are easier to diagnose because the source context is retained.

Use `--no-source-info` only when you need smaller payloads or do not want to carry raw source values forward.

```bash
convert-pheno -iomop PERSON.csv CONCEPT.csv \
  -obff individuals.json \
  --no-source-info
```

## Ontology Search Audit

For mapping-file workflows, use `--search-audit-tsv` to write a user-readable TSV of ontology lookups.

```bash
convert-pheno -icsv clinical.csv \
  --mapping-file mapping.yaml \
  --search-audit-tsv search-audit.tsv \
  -obff individuals.json
```

The audit file is useful for checking:

- the original label from the input
- the converted label
- the converted ontology identifier
- the ontology source
- whether the result came from an exact match, a fuzzy/mixed search, or a fallback

## Validators

Convert-Pheno development uses external validators when possible:

| Output | Validation Strategy |
|--------|---------------------|
| BFF | Validate entity JSON files such as `individuals.json`, `biosamples.json`, `datasets.json`, or `cohorts.json` against Beacon v2 Models |
| OMOP-CDM | Validate emitted CSV tables against the OMOP-CDM DDL |
| PXF | Validate through the extended Perl test suite |

:::note[BFF entity filenames]
BFF validators usually infer the entity from the file name. Use standard names such as `individuals.json`, `biosamples.json`, `datasets.json`, and `cohorts.json`.
:::

## Conversion Status

| Route | Status | Notes |
|-------|--------|-------|
| `PXF -> BFF individuals` | Mature | Core pathway |
| `BFF individuals -> PXF` | Mature | Used for round-trip conversion |
| `OMOP-CDM -> BFF individuals` | Mature | Depends on available OMOP tables and concept lookup |
| `PXF -> BFF biosamples` | Beta | Uses Phenopackets biosample content when present |
| `OMOP SPECIMEN -> BFF biosamples` | Beta | Supports structured biosample measurements for specimen quantity |
| `CSV`, `REDCap`, `CDISC-ODM` -> BFF | Beta | Depends on mapping-file quality |
| `openEHR -> BFF/PXF` | Experimental | Canonical composition support is still evolving |
