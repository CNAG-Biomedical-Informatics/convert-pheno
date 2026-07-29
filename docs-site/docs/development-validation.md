---
title: Development Validation
sidebar_label: Development Validation
---

This page records how generated output is checked while conversion mappings are developed and maintained. It is a development methodology, not an extra command that users are expected to run after every conversion.

These checks assess structural conformance and known mapping behavior. They do not establish the clinical correctness or completeness of a source dataset, and they do not imply that every vendor or project profile has been independently reviewed.

<div className="convertNotePanel">
  <p>
    Development loop: generate output, validate it, inspect schema or table
    errors, update mappings/defaults/type coercions in the runtime code, and
    repeat until the generated files validate for the tested route.
  </p>
</div>

## Validation Methods

During development, generated outputs are checked with external validators where practical:

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

## Implementation and Validation Evidence

`Supported` means that the route is implemented and covered by automated regression tests. It does not imply that every source profile or project-specific mapping has been independently reviewed. The validation column records that separate evidence.

| Route | Implementation | Validation experience |
|-------|----------------|-----------------------|
| `PXF -> BFF individuals` | Supported | Regression- and schema-validated core pathway |
| `BFF individuals -> PXF` | Supported | Regression- and protobuf-validated round-trip pathway |
| `OMOP-CDM -> BFF individuals` | Supported | Tested with synthetic and larger OMOP datasets; output depends on available tables and concept lookup |
| `PXF -> BFF biosamples` | Supported | Regression- and schema-validated; independent use remains limited |
| `OMOP SPECIMEN -> BFF biosamples` | Supported | Regression- and schema-validated; broader external validation is pending |
| `CSV -> BFF/PXF/supported OMOP-CDM tables` | Supported | Regression-tested; semantic results depend on the project mapping and terminology review |
| `REDCap -> BFF/PXF/supported OMOP-CDM tables` | Supported | Regression-tested; validation across diverse project structures is ongoing |
| `CDISC-ODM v1 -> BFF/PXF/supported OMOP-CDM tables` | Supported profile | Regression-tested for the documented ODM-XML v1 structure; broader vendor coverage is limited |
| `openEHR -> BFF/PXF` | Experimental | Canonical composition support and source-profile coverage are still evolving |
