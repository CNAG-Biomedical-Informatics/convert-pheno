---
title: Development Validation
sidebar_label: Development Validation
---

Convert-Pheno's reference outputs are checked while mappings are developed and
when conversion code changes. These are project development checks, not an
extra command required after every user conversion.

They test file structure and known mapping behavior. They cannot establish the
clinical correctness or completeness of a source dataset, and coverage varies
between source profiles.

<div className="convertNotePanel">
  <p>
    During development we generate a reference output, run the relevant
    validator, inspect any errors, and update the mapping or data handling. The
    cycle is repeated until the tested fixture passes.
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

The OMOP-to-BFF mapping bridges those structures. Reference BFF files are
checked with `bff-tools validate`, and schema errors are corrected in the
runtime mapping, defaults, or type handling. Some defaults exist because Beacon
requires a value for which the source OMOP row has no direct equivalent.

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
| `CDISC-ODM 1.3/2.0 Snapshot -> BFF/PXF/supported OMOP-CDM tables` | Supported REDCap profile; experimental generic profiles | REDCap ODM output is regression-tested against the established fixture; synthetic OpenClinica 1.3.2 and ODM 2.0 fixtures cover version detection, embedded metadata, nested/repeated groups, and occurrence-aware mapping |
| `cBioPortal clinical study -> BFF/PXF/supported OMOP-CDM tables` | Experimental clinical profile | Attributed DataHub package checked with the official cBioPortal validator; generated BFF entities and OMOP tables are checked with their target validators |
| `CDISC Dataset-JSON v1.1 SDTM -> BFF/PXF/supported OMOP-CDM tables` | Experimental profile | Schema- and semantic-input checks plus regression fixtures; BFF/PXF outputs and OMOP CDM 5.4 CSV tables are validator-checked, while broader study coverage is limited |
| `CDISC Dataset-XML v1.0 SDTM + Define-XML v2 -> BFF/PXF/supported OMOP-CDM tables` | Experimental profile | Cross-file metadata/reference checks and shared SDTM regression tests; generated target formats are checked with the corresponding external validators |
| `FHIR R4 / mCODE 4.0 Bundle -> BFF/PXF/supported OMOP-CDM tables` | Experimental profile | Reference-resolution and semantic regression tests using generic and official mCODE Bundles; BFF entities, Phenopackets output, and OMOP CDM 5.4 CSV tables are checked with the corresponding external validators; broader profile coverage is limited |
| `openEHR -> BFF/PXF` | Experimental | Canonical composition support and source-profile coverage are still evolving |
| `i2b2 table exports -> BFF/PXF/supported OMOP-CDM tables` | Experimental profile | Synthetic star-schema fixtures cover patient grouping, concepts, visits, and fact classification; generated BFF fixtures pass schema validation |
| `PCORnet CDM table exports -> BFF/PXF/supported OMOP-CDM tables` | Experimental profile | Synthetic v7-shaped fixtures cover demographics and major clinical tables; generated BFF fixtures pass schema validation |
| `Sentinel CDM table exports -> BFF/PXF/supported OMOP-CDM tables` | Experimental profile | Synthetic table fixtures cover demographics and major clinical tables; generated BFF fixtures pass schema validation |
