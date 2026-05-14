---
title: Output Validation
sidebar_label: Output Validation
---

# Output Validation

Output validation in Convert-Pheno is not a single switch. During development, converted files are checked against the target schemas or table definitions, and validation errors are used to improve the conversion code. For users, the same idea shows up as preserved source values, ontology search audit files, and documented mapping tables.

The goal is practical: converted files should be structurally valid, and users should still be able to inspect how source values became target fields.

<div className="convertNotePanel">
  <p>
    Development loop: generate output, validate it, inspect schema or table
    errors, update mappings/defaults/type coercions in the runtime code, and
    repeat until the generated files validate for the tested route.
  </p>
</div>

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

For mapping-file conversions, use `--search-audit-tsv` to write a user-readable TSV of ontology lookups.

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

## Development Validators

Convert-Pheno does not validate source files as clinical truth. Input validation and cleaning remain the user's responsibility.

During development, generated outputs are checked with external validators where practical.

- **BFF:** Beacon v2 JSON entities are checked with `bff-tools validate` from [beacon2-cbi-tools](https://github.com/CNAG-Biomedical-Informatics/beacon2-cbi-tools). Validator failures are used to update runtime mapping logic, defaults, and type coercions until generated entity files validate against the Beacon v2 schemas.
- **PXF:** Phenopackets output is checked in the extended `xt/protobuff.t` test. The test uses Inline Python to parse generated PXF JSON into the Phenopackets protobuf model with `google.protobuf.json_format.Parse` and `phenopackets.Phenopacket`.
- **OMOP-CDM:** Emitted OMOP CSV tables are checked with [omop-csv-validator](https://github.com/CNAG-Biomedical-Informatics/omop-csv-validator), which validates table files against the OMOP-CDM DDL.

:::note[BFF entity filenames]
BFF validators usually infer the entity from the file name. Use standard names such as `individuals.json`, `biosamples.json`, `datasets.json`, and `cohorts.json`.
:::

## OMOP-CDM to Beacon Validation

OMOP-CDM v5.4 is a relational SQL model, while Beacon v2 Models are hierarchical JSON schemas. For example, OMOP stores clinical facts across tables such as `PERSON`, `CONDITION_OCCURRENCE`, `MEASUREMENT`, `OBSERVATION`, `PROCEDURE_OCCURRENCE`, and `SPECIMEN`; Beacon `individuals` and `biosamples` represent related information as nested JSON objects.

The OMOP-to-BFF mappings were developed to bridge that difference while keeping the converted JSON structurally valid against Beacon v2 schemas. During development, generated BFF files were iteratively validated with `bff-tools validate`; schema errors were then addressed in the runtime conversion code by refining mappings, adding required defaults, and correcting data types. This is why some apparently artificial defaults exist: they are there to satisfy required Beacon structure when the source model has no direct equivalent.

Validation was also supported by dataset-specific checks:

- Synthetic EUNOMIA data were used where expected behavior can be checked under controlled conditions.
- Representative mappings were reviewed manually for semantic consistency.
- Larger OMOP datasets exposed edge cases that were used to refine the mapping with feedback from data owners.

The current OMOP-to-Beacon mapping tables are documented in [OMOP to BFF](omop2bff).

## OMOP Mapping Considerations

Two choices are important when reviewing OMOP-derived BFF:

- **Source preservation:** Original OMOP row values are retained under `info` or `_info` provenance blocks by default. This helps domain experts cross-check converted records and allows source-specific OMOP values to remain queryable when BFF is loaded into downstream systems. Use `--no-source-info` if you do not want to carry those raw values forward.
- **Exposure selection:** Beacon `exposures` are populated from a curated set of OMOP `concept_id` values. The candidate list is maintained in [`share/db/concepts_candidates_2_exposure.csv`](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/share/db/concepts_candidates_2_exposure.csv).

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
