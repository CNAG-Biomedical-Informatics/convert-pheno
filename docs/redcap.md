!!! Warning "Experimental"
    REDCap conversion is still experimental. Please use it with caution.

**REDCap** stands for **R**esearch **E**lectronic **D**ata **Cap**ture. REDCap [documentation](https://www.project-redcap.org).

## REDCap as input

REDCap projects are inherently **"free format"**, meaning the project creator has the flexibility to determine the identifiers for variables, data dictionaries, and other elements.

!!! Quote "REDCap project creation user’s guide" 
    _“We always recommend reviewing your variable names with a statistician or whoever will be analyzing your data. This is especially important if this is the first time you are building a database.”_ 

Due to the flexibility of REDCap projects, it can be challenging to develop a solution that accommodates the wide range of possibilities. Nonetheless, we were able to successfully convert data from REDCap project exports to both Beacon v2 and Phenopackets v2 formats using a mapping file. These conversions were achieved as part of the [3TR Project](https://3tr-imi.eu).

??? Warning "About REDCap longitudinal data"
    REDCap stores `event` information, however, [Beacon v2 Models](https://docs.genomebeacons.org/schemas-md/individuals_defaultSchema) currently lack a way to store longitudinal data. To address this, we will store `event` data under the propery `info`.

=== "Command-line"

    ??? Tip "About REDCap export formats"
        REDCap provides various options for exporting data. We accept the option "All data (all records and fields)" including CSV and Microsoft Excel format, along with an accompanying data dictionary in CSV format. Exportation in REDCap CDISC ODM (XML) format is discussed in the section on [CDISC-ODM](cdisc-odm.md).

    !!! Warning "Keep REDCap text exports as UTF-8 text files"
        Do not open and resave REDCap CSV exports or CSV data dictionaries with spreadsheet software such as Excel before running `convert-pheno`. This may alter UTF-8 encoding and corrupt non-ASCII characters such as `µ`, `≥`, accents, or degree symbols, which can then break dictionary values and ontology mappings.

    We'll need three files:

    1. REDCap export (CSV)
    2. REDCap data dictionary (CSV)
    3. Mapping file (YAML or JSON) (see [tutorial](tutorial.md))

    ??? Question "Can CSV files be compressed?"
        Yes. We also accept as **input** files compressed with `gzip`.

    ```
    convert-pheno -iredcap redcap.csv --redcap-dictionary dictionary.csv --mapping-file mapping.yaml -obff individuals.json
    ```

    If you want to inspect ontology search results, you can also request a TSV audit file:

    ```bash
    convert-pheno -iredcap redcap.csv --redcap-dictionary dictionary.csv --mapping-file mapping.yaml -obff individuals.json --search-audit-tsv search-audit.tsv
    ```

    If you also want synthesized Beacon `datasets` and `cohorts`, keep `-obff` and use entity mode:

    ```bash
    convert-pheno -iredcap redcap.csv --redcap-dictionary dictionary.csv --mapping-file mapping.yaml -obff --entities individuals datasets cohorts --out-dir out/
    ```

    In this mode, the top-level `beacon` section of the mapping file can override dataset and cohort metadata such as `id`, `name`, `description`, `version`, or `cohortType`.

    The audit file is tab-separated and currently includes columns such as:

    - `row`
    - `original_term_label`
    - `converted_term_label`
    - `converted_term_id`
    - `ontology`
    - `match_status`
    - `match_source`

    This is useful when users want to review how REDCap source values were resolved against SQLite-backed ontologies before trusting the final conversion.

=== "API"

    While it is _technically possible_ to perform a transformation via API we don't think it's a viable option with REDCap projects due to the need for loading the data dictionary and mapping files along with the data. Therefore, we recommend using the **command-line** version by utilizing REDCap data exports.

    If you still want to call the API, the request payload uses explicit `conversion`, `input`, and `options` sections:

    ```json
    {
      "conversion": "redcap2bff",
      "input": {
        "in_file": "redcap.csv",
        "redcap_dictionary": "dictionary.csv",
        "mapping_file": "mapping.yaml"
      },
      "options": {
        "search": "exact"
      }
    }
    ```

    ??? Warning "REDCap built in API"
        REDCap has a built-in API that in theory could be used to retrieve data in real-time (as opposed to data exports). However, the current version of `Convert-Pheno` does not support REDCap API calls.
    --8<-- "tbl/formats.md"
