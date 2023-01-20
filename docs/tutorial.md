This page provides brief tutorials on how to perform data conversion.

!!! Info "Note on installation"
    Before proceeding, ensure that the software is properly installed. In the following instructions, it will be assumed that you have downloaded and installed the [containerized version](https://github.com/mrueda/convert-pheno#containerized).

### How to convert:

=== "REDCap to Phenopackets v2"

    This section provides a summary of the steps to convert a REDCap project to Phenopackets v2. The starting point is to log in to your REDCap system and export the data to CSV format. If you need more information on REDCap, we recommend consulting the comprehensive [documentation](https://confluence.research.cchmc.org/display/CCTSTRED/Cincinnati+REDCap+Resource+Center) provided by the Cincinnati Children's Hospital Medical Center.

    After exporting the data, you must also download the REDCap dictionary in CSV format. This can be done within REDCap by navigating to `Project Setup/Data Dictionary/Download the current`.

    Since REDCap projects are "free-format," a mapping file is necessary to connect REDCap project variables (i.e. fields) to something meaningful for `Convert-Pheno`. This mapping file will be used in the conversion process.

    !!! Question "What is a `Convert-Pheno` mapping file?"
        A mapping file is a text file in [YAML](https://en.wikipedia.org/wiki/YAML) format ([JSON]((https://en.wikipedia.org/wiki/JSON) is also accepted) that connects a set of variables to a format that is understood by `Convert-Pheno`. This file maps your variables to the required **terms** of the [individuals](https://docs.genomebeacons.org/schemas-md/individuals_defaultSchema) entity from the Beacon v2 models.

    ### Creating a mapping file

    To create a mapping file, start by reviewing the [reference](https://github.com/mrueda/convert-pheno/blob/main/t/redcap2bff/in/redcap_3tr_mapping.yaml) provided with the installation. The goal is to replace the contents with those from your REDCap project. The mapping file contains the following types of data:

    | Type        | Required    | Required properties | Optional properties |
    | ----------- | ----------- | ------------------- | ------------------- |
    | Internal    | `project`   | `id, source, ontology` | ` description` |
    | Beacon v2 terms   | `diseases, exposures, id, info, interventionsOrProcedures, measures, phenotypicFeatures, sex, treatments` | `fields`| `dict, radio, routes` |

     * These are the properties needeed to map your data to the entity `individuals` in the Beacon v2 Models:
        - **fields**, an `array` of REDCap variables that map to that term.
        - **dict**, an `object` in the form of `key: value` with specific mappings.
        - **radio**, a nested `object` value with specific mappings.
        - **routes**, an `array` with specific mappings.

    !!! Tip "Defining the values in the property `fields`"
        The values are obtained from the ontology you have selected in `project.ontology`. For example, if you have chosen `ncit`, you can search for the values within NCIT at [EBI Search](https://www.ebi.ac.uk/ols/ontologies/ncit). `Convert-Pheno` will use these values to retrieve the actual ontology from its internal databases".

    ### Running `Convert-Pheno`

    Once you have created the mapping file you can proceed to run `convert-pheno` with the **command-line interface**. Please see how [here](redcap.md#redcap-as-input).
 
=== "OMOP-CDM to Beacon v2 Models"

    This section provides a summary of the steps to convert an OMOP-CDM export to Beacon v2 Models. The starting point is either a PostgreSQL export in the form of `.sql` or `.csv` files. The process is the same for both.

    Two possibilities may arise:

    1. **Full** export of records.
    2. **Partial** export of records.

    #### Full export 

    In a full export, all ontologies are included in the `CONCEPT` table, thus Convert-Pheno does not need to search any additional databases for ontologies (with a few exceptions). 

    #### Partial export

    In a partial export, many ontologies may be missing from the `CONCEPT` table, as a result, `Convert-Pheno` will perform a search on the included **ATHENA-OHDSI** database. To enable this search you should use the flag `---ohdsi-db`.

    ### Running `Convert-Pheno`

    Once you have created the mapping file you can proceed to run `convert-pheno` with the **command-line interface**. Please see how [here](omop-cdm.md#omop-as-input).

!!! Question "More questions?"
    Pease take a look to our [Frequently Asked Questions](faq.md).

