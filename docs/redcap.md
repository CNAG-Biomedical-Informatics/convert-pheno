!!! Danger "Experimental"
    REDCap conversion is still experimental. It only works with controlled REDCap projects.

**REDCap** stands for **R**esearch **E**lectronic **D**ata **Cap**ture. REDCap [documentation](https://www.project-redcap.org).

## REDCap as input

REDCap projects are by definition “**free format**”, that is, is up to the project creator to establish the identifiers for the variables, data dictionaries, etc. 

!!! Info 
    As stated in the REDCap project creation user’s guide _“We always recommend reviewing your variable names with a statistician or whoever will be analyzing your data. This is especially important if this is the first time you are building a database.”_ 

This freedom of choice makes very difficult (if not impossible) to come up with a solution that is able to handle the plethora of possibilities from REDCap projects. Still, we have been able to succesfully convert data from REDCap project exports to both Beacon v2 and Phenopackets v2. These projects were developed in the context of the [3TR Project](https://3tr-imi.eu).

=== "Command-line"

    !!! Important "About REDCap export formats"
        REDCap allows for exporting "All data (all records and fields)" in multiple ways. Here we are accepting the `CSV / Microsoft Excel` format, along with a data dictionary (also in CSV).
        REDCap `CDISC ODM (XML)` export will be covered in the section about [CDISC-ODM](cdisc.md).


    We'll need three files:

    1. REDCap export (CSV)
    2. REDCap data dictionary (CSV)
    3. Configuration (mapping) file (YAML)

    ```
    convert-pheno -iredcap redcap.csv --redcap-dictionary dictionary.csv --redcap-config config.yaml -obff individuals.json
    ```

    During the data transformation, **ontologies are automatically added** to harmonize the content of the variables. We use [NCI Thesaurus](https://ncithesaurus.nci.nih.gov/ncitbrowser), [ICD-10](https://icd.who.int/browse10), and data from [Athena-OHDSI](https://athena.ohdsi.org/search-terms/start).

=== "API"

    Yet _a priori_ is possible to send data via API, we haven't encountered such case yet. Thus, **we recommend using the command-line version** by using data exports.

    !!! Warning "REDCap built in API"
        REDCap has a built API, which, in principle could be used to pull data _on-the-fly_ data (instead of data exports).
        The current version of `Convert::Pheno` does not support REDCap API calls.
