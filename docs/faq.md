Frequently Asked Questions

## General

??? faq "What does `Convert-Pheno` do?"

    `Convert-Pheno` is an open-source toolkit for converting clinical and phenotypic data between supported exchange models such as `BFF`, `PXF`, `OMOP-CDM`, `REDCap`, `CDISC-ODM`, and mapped `CSV`.


??? faq "Is `Convert-Pheno` free?"

    Yes. See the [license](https://github.com/mrueda/convert-pheno/blob/main/LICENSE).


??? faq "Is `Convert-Pheno` or `Pheno-Convert`?"

    It's **`Convert-Pheno`**, for two reasons:

    1. The naming is inspired by the `convert` utility from [ImageMagick](https://imagemagick.org).
    2. In related contexts, people refer to *PhenoConvert* as in [PhenoCopy](https://en.wikipedia.org/wiki/Phenocopy) or [PhenoConversion](https://www.universiteitleiden.nl/en/research/research-projects/science/phenoconversion).


??? faq "Is `Convert-Pheno` ready for use in production environments?"
    The software is fully functional and has been successfully used in several European-funded projects. However, it is still in beta, so ongoing improvements and refinements are to be expected.


??? faq "If I use `Convert-Pheno` to convert my data to [Beacon v2 Models](bff.md), does this mean I have a Beacon v2?"

    No. Beacon v2 is an [API specification](https://docs.genomebeacons.org), while the [Beacon v2 Models](bff.md) are the data models used by that API. `Convert-Pheno` helps generate compatible data files, but a working Beacon still needs storage and an API layer on top.


??? faq "What is the difference between Beacon v2 Models and Beacon v2?"

    **Beacon v2** is a specification to build an [API](https://docs.genomebeacons.org). The [Beacon v2 Models](https://docs.genomebeacons.org/models/) define the format for the API's responses to queries regarding biological data. With the help of `Convert-Pheno`, data exchange text files ([BFF](bff.md)) that align with this response format can be generated. By doing so, the BFF files can be integrated into a non-SQL database, such as MongoDB, without the API having to perform any additional data transformations internally.


??? faq "Why are there so many clinical data standards?"

    Different standards solve different problems: clinical care, research harmonization, case reporting, API exchange, or project-level data capture. `Convert-Pheno` exists because those formats overlap in practice, but they were not designed as one unified ecosystem.


??? faq "Are you planning in supporting other clinical data formats?"

    Afirmative, but it will depend on community adoption. Please check our [roadmap](future-plans.md) for more information.


??? faq "Are longitudinal data supported?"

    Although Beacon v2 and Phenopackets v2 allow for storing time information in some properties, there is currently no way to associate medical visits to properties. To address this:

    * `omop2bff` -  we added an _ad hoc_ property (**_visit**) to store medical visit information for longitudinal events in variables that have it (e.g., measures, observations, etc.).

    * `redcap2bff` - In REDCap, visit/event information is not stored at the record level. We added this information inside `info` property.

    We raised this issue to the respective communities in the hope of a more permanent solution.


??? faq "What is an "ontology" in Beacon v2 and Phenopacket v2 context?"

    In this context, “ontology” is used broadly for standardized identifiers such as HPO, NCIt, LOINC, or RxNorm terms. In practice, these are the coded terms used in the JSON structures handled by Beacon v2 and Phenopackets.


??? faq "I have a collection of PXF files encoded using HPO and ICD-10 terms, and I need to convert them to BFF format, but encoded in OMIM and SNOMED-CT terminologies. Can you assist me with this?"

    Not directly. `Convert-Pheno` converts data models, but it does not rewrite source ontology terms into a different terminology system. If you need ontology remapping, that should be handled as a separate mapping step.



??? faq "What type of data validation is carried out?"

    --8<-- "md/data-validation.md"


??? faq "What type of **database search** is carried out?"

    --8<-- "tbl/db-search.md"


??? faq "Error Handling for `CSV_XS ERROR: 2023 - EIQ - QUO character not allowed @ rec 1 pos 21 field 1`"

    This usually means the file separator does not match what `Convert-Pheno` is expecting. See [Troubleshooting](troubleshooting.md#csv_xs-separator-error).


??? faq "Should I export my REDCap project as _raw data_ or as _labels_ for use with `Convert-Pheno`?"

    Prefer **raw data** together with the REDCap dictionary file. If your export uses labels instead, use the [CSV](csv.md) route. See [Troubleshooting](troubleshooting.md#redcap-export-mode).

??? faq "Can I use the mapping file to customize synthesized `datasets` and `cohorts` for any `*2bff` conversion?"

    No. Mapping-based augmentation of synthesized `datasets` and `cohorts` is currently available only for the routes that use a mapping file: `csv2bff`, `redcap2bff`, and `cdisc2bff`.

    For those workflows, the top-level `beacon` section of the mapping file can override metadata such as `id`, `name`, `description`, `version`, `externalUrl`, `cohortType`, or `cohortDataTypes`.

    This does not currently apply to `omop2bff` or `pxf2bff`.

??? faq "Which formats accept gzipped (`.gz`) files?"

    Based on the current I/O code, gzip support is available for these file families:

    | File family | Typical use | Read `.gz` | Write `.gz` | Notes |
    | --- | --- | --- | --- | --- |
    | JSON / YAML structured files | `BFF`, `PXF`, `JSON-LD`, flattened `JSON/YAML`, mapping files, schema files | Yes | Yes | Implemented through the shared JSON/YAML I/O layer for `.json`, `.yaml`, `.yml`, `.jsonld`, `.yamlld`, `.ymlld` and their `.gz` variants |
    | CSV / TSV / TXT tabular inputs | `csv2*`, `redcap2*`, REDCap dictionary files | Yes | N/A | Input readers accept `.csv.gz`, `.tsv.gz` and `.txt.gz` |
    | SQL dumps | `omop2*` from `.sql` dumps | Yes | N/A | OMOP SQL input accepts `.sql.gz` |
    | Streamed OMOP output | `omop2bff --stream` | N/A | Yes | CLI restricts streamed OMOP output to `json` or `json.gz` |
    | OMOP table output | `*2omop` | N/A | Yes | Use `-oomop --out-dir DIR` to get `TABLE.csv` files. Use `--out-name TABLE=filename.csv.gz` to rename or gzip specific tables |
    | CSV / TSV output | `bff2csv`, `pxf2csv`, search-audit TSV | N/A | Yes | The current writers accept `.csv.gz` and `.tsv.gz` in addition to plain text output |

    In practice, gzip is supported both for structured JSON/YAML-style outputs and for the main CSV/TSV output paths.


## Installation

??? faq "I am installing `Convert-Pheno` from source ([non-containerized version](download-and-installation.md#non-containerized)) but I can't make it work. Any suggestions?"

    See [Troubleshooting](troubleshooting.md#python-api--local-bridge-installation).
