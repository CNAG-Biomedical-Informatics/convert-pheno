!!! Bug "Experimental"
    REDCap conversion is still experimental. It only works with controlled REDCap projects.

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
        REDCap provides various options for exporting data. We accept the option "All data (all records and fields)" including CSV and Microsoft Excel format, along with a accompanying data dictionary in CSV format. Exportation in REDCap CDISC ODM (XML) format is discussed in the section on [CDISC-ODM](cdisc-odm.md).

    We'll need three files:

    1. REDCap export (CSV)
    2. REDCap data dictionary (CSV)
    3. Mapping file (YAML or JSON) (see [tutorial](tutorial.md))

    ??? Question "Can CSV files be compressed?"
        Yes. We also accept as **input** files compressed with `gzip`.

    ```
    convert-pheno -iredcap redcap.csv --redcap-dictionary dictionary.csv --mapping-file mapping.yaml -obff individuals.json
    ```

=== "API"

    While it is _technically possible_ to perform a transformation via API we don't think it's a viable option with REDCap projects due to the need for loading the data dictionary and mapping files along with the data. Therefore, we recommend using the **command-line** version by utilizing REDCap data exports.

    ??? Warning "REDCap built in API"
        REDCap has a built-in API that in theory could be used to retrieve data in real-time (as opposed to data exports). However, the current version of `Convert-Pheno` does not support REDCap API calls.
    --8<-- "tbl/formats.md"
