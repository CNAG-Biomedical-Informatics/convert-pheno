??? Tip "Google Colab version"
     We created a [Google Colab version](https://colab.research.google.com/drive/1T6F3bLwfZyiYKD6fl1CIxs9vG068RHQ6) of the tutorial. Users can view notebooks shared publicly without sign-in, but you need a google account to execute code.

    <a target="_blank" href="https://colab.research.google.com/drive/1T6F3bLwfZyiYKD6fl1CIxs9vG068RHQ6">
      <img src="https://colab.research.google.com/assets/colab-badge.svg" alt="Open In Colab"/>
    </a>

    We also have a local copy of the notebook that can be downloaded from the [repo](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/nb/convert_pheno_cli_tutorial.ipynb). 

This page provides brief tutorials on how to perform data conversion by using `Convert-Pheno`**command-line interface**.

??? Info "Note on installation"
    Before proceeding, ensure that the software is properly installed. In the following instructions, it will be assumed that you have downloaded and installed [Convert-Pheno](./download-and-installation.md).

### How to convert:

=== "REDCap to Phenopackets v2"

    This section provides a summary of the steps to convert a REDCap project to Phenopackets v2. 

    * The starting point is to log in to your REDCap system and export the data to CSV / Microsoft Excel (raw data) format. If you need more information on REDCap, we recommend consulting the comprehensive [documentation](https://confluence.research.cchmc.org/display/CCTSTRED/Cincinnati+REDCap+Resource+Center) provided by the Cincinnati Children's Hospital Medical Center.

    ??? Question "Can I export CSV / Microsoft Excel (labels) file?"

        Yes, you can export a CSV or Microsoft Excel file with labels. However, you need to use the `--icsv` flag instead of the `--iredcap` flag as the input format. While we recommend exporting raw data along with the dictionary for better accuracy, we understand that this might not always be possible.

        For more detailed information and other common questions, please refer to the [FAQ](faq.md#general).

    * After exporting the data, you must also download the REDCap dictionary in CSV format. This can be done within REDCap by navigating to `Project Setup/Data Dictionary/Download the current`.

    * Since REDCap projects are "free-format," a mapping file is necessary to connect REDCap project variables (i.e. fields) to something meaningful for `Convert-Pheno`. This mapping file will be used in the conversion process.

    --8<-- "tbl/mapping-file.md"

    --8<-- "tbl/db-search.md"

    ### Running `Convert-Pheno`

    Now you can proceed to run `convert-pheno` with the **command-line interface**. Please see how [here](csv.md#csv-as-input).

=== "OMOP CDM to Beacon v2 Models"

    This section provides a summary of the steps to convert an OMOP CDM export to Beacon v2 Models. The starting point is either a PostgreSQL export in the form of `.sql` or `.csv` files. The process is the same for both.

    Two possibilities may arise:

    1. **Full** export of records.
    2. **Partial** export of records.

    #### Full export 

    In a full export, all standardized terms are included in the `CONCEPT` table, thus Convert-Pheno does not need to search any additional databases for terminology (with a few exceptions). 

    #### Partial export

    In a partial export, many standardized terms may be missing from the `CONCEPT` table, as a result, `Convert-Pheno` will perform a search on the included **ATHENA-OHDSI** database. To enable this search you should use the flag `--ohdsi-db`.

    ### Running `Convert-Pheno`

    Now you can proceed to run `convert-pheno` with the **command-line interface**. Please see how [here](omop-cdm.md#omop-as-input).

=== "CSV to Beacon v2 Models"

    This section provides a summary of the steps to convert a CSV file with raw clinical data to Phenopackets v2.

    * Since CSV files  are "free-format," a mapping file is necessary to connect variables (i.e. fields) to something meaningful for `Convert-Pheno`. This mapping file will be used in the conversion process.

    --8<-- "tbl/mapping-file.md"

    ### Running `Convert-Pheno`

    Now you can proceed to run `convert-pheno` with the **command-line interface**. Please see how [here](csv.md#csv-with-clinical-data-as-input).

!!! Question "More questions?"
    Please take a look to our [Frequently Asked Questions](faq.md).

