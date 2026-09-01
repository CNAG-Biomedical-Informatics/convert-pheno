---
title: FAQs
sidebar_label: FAQs
---

# FAQs

## General

<details>
<summary>What does `Convert-Pheno` do?</summary>


`Convert-Pheno` is an open-source toolkit for converting clinical and phenotypic data between supported exchange models such as `BFF`, `PXF`, `OMOP-CDM`, `REDCap`, `CDISC-ODM`, CDISC `Dataset-JSON` and `Dataset-XML`, FHIR R4/mCODE, and mapped `CSV`.


</details>
<details>
<summary>Can `Convert-Pheno` be used as an ETL tool for CSV-to-OMOP?</summary>


Yes. Convert-Pheno can turn mapped CSV records into supported OMOP CSV tables
in one command. It uses BFF internally; you do not need to create an
intermediate BFF file.

You must provide a mapping file describing the source columns and their
meaning. Convert-Pheno writes OMOP CSV tables but does not import them into an
OMOP database. Review and validate the tables before importing them. See the
[CSV guide](csv) and [BFF to OMOP](bff2omop).


</details>
<details>
<summary>Is `Convert-Pheno` free?</summary>


Yes. See the [license](https://github.com/mrueda/convert-pheno/blob/main/LICENSE).


</details>
<details>
<summary>Is `Convert-Pheno` or `Pheno-Convert`?</summary>


It's **`Convert-Pheno`**, for two reasons:

1. The naming is inspired by the `convert` utility from [ImageMagick](https://imagemagick.org).
2. In related contexts, people refer to *PhenoConvert* as in [PhenoCopy](https://en.wikipedia.org/wiki/Phenocopy) or [PhenoConversion](https://www.universiteitleiden.nl/en/research/research-projects/science/phenoconversion).


</details>
<details>
<summary>How mature are the supported conversions?</summary>

Convert-Pheno is used in research projects, and its supported routes are
covered by automated regression tests. Formats marked **experimental** are
implemented, but have been evaluated with fewer independent datasets or source
systems. Validate generated outputs against your project's requirements before
operational use.


</details>
<details>
<summary>Were any mappings developed with LLM assistance?</summary>


Some newer mappings were drafted or refined with large language model (LLM)
assistance when the source standard was especially dense or ambiguous. LLM
output is not accepted as mapping evidence on its own: changes require human
review, regression testing, and relevant target-format validation.

Specific models and reasoning settings are development tools rather than part
of the public conversion contract. The mapping tables document implemented
behavior; the code, fixtures, schemas, and validators determine whether that
behavior is accepted.


</details>
<details>
<summary>If I use `Convert-Pheno` to convert my data to [Beacon v2 Models](bff), does this mean I have a Beacon v2?</summary>


No. Beacon v2 is an [API specification](https://docs.genomebeacons.org), while the [Beacon v2 Models](bff) are the data models used by that API. `Convert-Pheno` helps generate compatible data files, but a working Beacon still needs storage and an API layer on top.


</details>
<details>
<summary>What is the difference between Beacon v2 Models and Beacon v2?</summary>


**Beacon v2** is a specification to build an [API](https://docs.genomebeacons.org). The [Beacon v2 Models](https://docs.genomebeacons.org/models/) define the format for the API's responses to queries regarding biological data. With the help of `Convert-Pheno`, data exchange text files ([BFF](bff)) that align with this response format can be generated. By doing so, the BFF files can be integrated into a non-SQL database, such as MongoDB, without the API having to perform any additional data transformations internally.


</details>
<details>
<summary>Why are there so many clinical data standards?</summary>


Different standards solve different problems: clinical care, research harmonization, case reporting, API exchange, or project-level data capture. `Convert-Pheno` exists because those formats overlap in practice, but they were not designed as one unified ecosystem.


</details>
<details>
<summary>Are you planning in supporting other clinical data formats?</summary>


Afirmative, but it will depend on community adoption. Please check our [roadmap](future-plans) for more information.


</details>
<details>
<summary>Are longitudinal data supported?</summary>


Although Beacon v2 and Phenopackets v2 allow for storing time information in some properties, there is currently no way to associate medical visits to properties. To address this:

* `omop2bff` -  we added an _ad hoc_ property (**_visit**) to store medical visit information for longitudinal events in variables that have it (e.g., measures, observations, etc.).

* `redcap2bff` - In REDCap, visit/event information is not stored at the record level. We added this information inside `info` property.

We raised this issue to the respective communities in the hope of a more permanent solution.


</details>
<details>
<summary>What is an "ontology" in Beacon v2 and Phenopacket v2 context?</summary>

In this context, “ontology” is used broadly for standardized identifiers such as HPO, NCIt, LOINC, or RxNorm terms. In practice, these are the coded terms used in the JSON structures handled by Beacon v2 and Phenopackets.

</details>

<details>
<summary>I have a collection of PXF files encoded using HPO and ICD-10 terms, and I need to convert them to BFF format, but encoded in OMIM and SNOMED-CT terminologies. Can you assist me with this?</summary>


Not directly. `Convert-Pheno` converts data models, but it does not rewrite source ontology terms into a different terminology system. If you need ontology remapping, that should be handled as a separate mapping step.



</details>
<details>
<summary>What type of data validation is carried out?</summary>

Convert-Pheno uses external validators during development where practical: `bff-tools validate` from [beacon2-cbi-tools](https://github.com/CNAG-Biomedical-Informatics/beacon2-cbi-tools) for Beacon/BFF output, the extended `xt/protobuff.t` protobuf parsing test for PXF output, and [omop-csv-validator](https://github.com/CNAG-Biomedical-Informatics/omop-csv-validator) for OMOP CSV output. For BFF mappings, validator failures are used to refine runtime mappings, defaults, and type coercions until generated entity files validate against the Beacon v2 schemas.

Convert-Pheno does **not** validate the clinical correctness or completeness of your input data. Source files should be checked before conversion.

See [Development Validation](development-validation) for details.
</details>
<details>
<summary>What type of **database search** is carried out?</summary>

Convert-Pheno supports indexed exact lookup, strict token ranking with `mixed`,
and typo-tolerant candidate retrieval with `fuzzy`. Similarity scores measure
lexical resemblance rather than clinical equivalence. The formulas, worked
NCIT example, threshold behavior, and terminology-audit columns are documented
under [Terminology Search](terminology-search).

</details>
<details>
<summary>Why do some Dataset-JSON and Dataset-XML examples contain `CDISC:` identifiers?</summary>

Those identifiers are deliberate source-derived fallbacks, not failed or
silently skipped searches. Convert-Pheno does not invent an external ontology
crosswalk when the source supplies no authoritative identifier and the data
owner has not configured a terminology rule.

The repository keeps baseline and terminology-enriched fixtures separately.
Baseline outputs test structural conversion and preservation of SDTM
field/value identity. Enriched outputs test reviewed mapping-file queries,
direct terms, or exact NCI identifier lookup from Define-XML. Use
`--term-audit` to distinguish each resolution path in your own conversion.

See [Dataset-JSON](dataset-json), [Dataset-XML](dataset-xml), and
[Terminology Search](terminology-search).

</details>
<details>
<summary>Error Handling for `CSV_XS ERROR: 2023 - EIQ - QUO character not allowed @ rec 1 pos 21 field 1`</summary>


This usually means the file separator does not match what `Convert-Pheno` is expecting. See [Troubleshooting](troubleshooting#csv_xs-separator-error).


</details>
<details>
<summary>Should I export my REDCap project as _raw data_ or as _labels_ for use with `Convert-Pheno`?</summary>


Prefer **raw data** together with the REDCap dictionary file. If your export uses labels instead, use the [CSV](csv) route. See [Troubleshooting](troubleshooting#redcap-export-mode).

</details>
<details>
<summary>Can I use the mapping file to customize synthesized `datasets` and `cohorts` for any `*2bff` conversion?</summary>


Yes, for supported entity-aware BFF routes. Mapping V2 has two relevant forms:

- CSV, REDCap, and CDISC-ODM use full mappings because their source fields are project-specific. cBioPortal can optionally augment its built-in clinical mapping.
- OMOP, PXF, FHIR, openEHR, i2b2, PCORnet, and Sentinel use a compact optional metadata mapping. Their structural conversion remains built in.

In both forms, `project.id`, `beacon.datasets.defaults`, and
`beacon.cohorts.defaults` can identify and describe synthesized entities.
Dataset-JSON and Dataset-XML instead prepopulate this metadata from `studyOID`
and the `TS` study title; their optional mapping is for terminology enrichment.

FHIR metadata from `ResearchStudy` and `Group` is retained as the source-derived
baseline and can be overridden by the compact mapping. Project metadata is not
currently copied into individual or biosample records.

</details>
<details>
<summary>Which formats accept gzipped (`.gz`) files?</summary>


Based on the current I/O code, gzip support is available for these file families:

| File family | Typical use | Read `.gz` | Write `.gz` | Notes |
| --- | --- | --- | --- | --- |
| JSON / YAML structured files | `BFF`, `PXF`, `JSON-LD`, flattened `JSON/YAML`, mapping files, schema files | Yes | Yes | Implemented through the shared JSON/YAML I/O layer for `.json`, `.yaml`, `.yml`, `.jsonld`, `.yamlld`, `.ymlld` and their `.gz` variants |
| CSV / TSV / TXT tabular inputs | `csv2*`, `redcap2*`, REDCap dictionary files | Yes | N/A | Input readers accept `.csv.gz`, `.tsv.gz` and `.txt.gz` |
| SQL dumps | `omop2*` from `.sql` dumps | Yes | N/A | OMOP SQL input accepts `.sql.gz` |
| Streamed OMOP output | `omop2bff --stream` | N/A | Yes | CLI restricts streamed OMOP output to `json` or `json.gz` |
| OMOP table output | `*2omop` | N/A | Yes | Use `-oomop --out-dir DIR` to get `TABLE.csv` files. Use `--out-name TABLE=filename.csv.gz` to rename or gzip specific tables |
| CSV / TSV output | `bff2csv`, `pxf2csv`, terminology-audit TSV | N/A | Yes | The current writers accept `.csv.gz` and `.tsv.gz` in addition to plain text output |

In practice, gzip is supported both for structured JSON/YAML-style outputs and for the main CSV/TSV output paths.


</details>
## Installation

<details>
<summary>I am installing `Convert-Pheno` from source ([non-containerized version](download-and-installation#non-containerized)) but I can't make it work. Any suggestions?</summary>


See [Troubleshooting](troubleshooting#python-api--local-bridge-installation).
</details>
