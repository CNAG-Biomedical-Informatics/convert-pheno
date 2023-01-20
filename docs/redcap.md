!!! Bug "Experimental"
    REDCap conversion is still experimental. It only works with controlled REDCap projects.

**REDCap** stands for **R**esearch **E**lectronic **D**ata **Cap**ture. REDCap [documentation](https://www.project-redcap.org).

## REDCap as input

REDCap projects are inherently **"free format"**, meaning the project creator has the flexibility to determine the identifiers for variables, data dictionaries, and other elements.

!!! Quote "REDCap project creation user’s guide" 
    _“We always recommend reviewing your variable names with a statistician or whoever will be analyzing your data. This is especially important if this is the first time you are building a database.”_ 

Due to this flexibility, it can be challenging to create a solution that can handle the vast array of possibilities in REDCap projects. Despite this, we were able to successfully convert data from REDCap project exports to both Beacon v2 and Phenopackets v2 by utilizing a mapping file. These conversions were achieved as part of the [3TR Project](https://3tr-imi.eu).

=== "Command-line"

    !!! Tip "About REDCap export formats"
        REDCap provides various options for exporting data. We accept the option "All data (all records and fields)" including CSV and Microsoft Excel format, along with a accompanying data dictionary in CSV format. Exportation in REDCap CDISC ODM (XML) format is discussed in the section on [CDISC-ODM](cdisc.md).

    We'll need three files:

    1. REDCap export (CSV)
    2. REDCap data dictionary (CSV)
    3. Mapping file (YAML or JSON)

    ```
    convert-pheno -iredcap redcap.csv --redcap-dictionary dictionary.csv --mapping-file mapping.yaml -obff individuals.json
    ```

    !!! Abstract "Ontologies used"
        During the data transformation process, **ontologies** are automatically added to standardize the content of the variables. We use [NCI Thesaurus](https://ncithesaurus.nci.nih.gov/ncitbrowser), [ICD-10](https://icd.who.int/browse10), and data from [Athena-OHDSI](https://athena.ohdsi.org/search-terms/start).

=== "API"

    While it is technically possible to send data via API, we have not yet encountered such a case. Therefore, we recommend using the **command-line** version by utilizing data exports.

    !!! Warning "REDCap built in API"
        REDCap has a built-in API that in theory could be used to retrieve data in real-time (as opposed to data exports). However, the current version of `Convert-Pheno` does not support REDCap API calls.
