In this page you will find brief tutorials on how to perform data conversion.

!!! Info "Note on installation"
    Before proceeding make sure you have the software properly installed. From now on, we will assume you downloaded and installed the [containerized version](https://github.com/mrueda/convert-pheno#containerized).

### How to convert:

=== "REDCap to Phenopackets v2"

    Here we will summarize the necessary steps to convert a [REDCap project](redcap.md) to [Phenopackets v2](pxf.md). 
    Your starting point will be to log into your REDCap system and perform a REDCap export to CSV. If you need more information on REDCap we recommend you to check this comprehensive [documentation](https://confluence.research.cchmc.org/display/CCTSTRED/Cincinnati+REDCap+Resource+Center) from Cincinnati Children's Hospital Medical Center.

    After performing the export, you need to also to download a REDCap dictionary in `CSV` format. The download is carried out inside REDCap at `Project Setup/Data Dictionary/Download the current`.

    Since REDCap projects are "free-format" we need a way to connect REDCap project variables (a.k.a., fields) to something meaningful for `Convert-Pheno`. In order to do this, we will be usign a **mapping file**.

    !!! Question "What is a `Convert-Pheno` mapping file?"
        A mapping file is a text file in [YAML](https://en.wikipedia.org/wiki/YAML) format ([JSON](https://en.wikipedia.org/wiki/JSON) is also accepted) that connects a set of variables to a format understood by `Convert-Pheno`. Inside the file, your variables are mapped to the required **terms** of the entity `individuals` from the [Beacon v2 models](https://docs.genomebeacons.org/schemas-md/individuals_defaultSchema/).

    ### Creating a mapping file

    To create a mapping file start by looking at the [reference](https://github.com/mrueda/convert-pheno/blob/main/t/redcap2bff/in/redcap_3tr_mapping.yaml) provided with the installation. The idea is to replace the contents with that from you REDCap project. In the mapping file you will find these types of data:

    | Type        | Required    | Required Properties | Optional Properties |
    | ----------- | ----------- | ------------------- | ------------------- |
    | Internal    | `project`   | `projectId, projectType` | |
    | Beacon v2 terms   | `diseases, exposures, info, interventionsOrProcedures, measures, phenotypicFeatures, sex, treatments` | `fields`| `dict, radio, routes` |

     * Beacon v2 terms correspond to the entity `individuals`. These are the properties:
        - **fields**, an `array` of REDCap variables that map that term.
        - **dict**, an `object` in the form of `key: value` with specific mappings.
        - **radio**, a nested `object` value with specific mappings.
        - **routes**, an `array` with specific mappings.

    ### Running `Convert-Pheno`

    Once you have created the mapping file you can proceed to run `convert-pheno` with the **command-line interface**. Please see how [here](redcap.md#redcap-as-input).
 
=== "OMOP-CDM to Beacon v2 Models"

    Here we will summarize the necessary steps to convert an [OMOP-CDM export](omop-cdm.md) to [Beacon v2 Models](bff.md).
    Your starting point will be either a PostgreSQL export in the form of `.sql` or `.csv` files. The operation is the same for both.

    Two possibilities may arise:

    1. **Full** export of records.
    2. **Partial** export of records.

    #### Full export 

    In a full export, all ontologies are included on the table `CONCEPT`, thus, `Convert-Pheno` does not have to perform a search on any database to find ontologies (with the exception of a few fields).

    #### Partial export

    In a partial export, many ontologies may be missing on the table `CONCEPT`, thus, `Convert-Pheno` does will perform a search on the included **ATHENA-OHDSI** database. To enable this search you should use the flag `---ohdsi-db`.

    ### Running `Convert-Pheno`

    Once you have created the mapping file you can proceed to run `convert-pheno` with the **command-line interface**. Please see how [here](omop-cdmredcap.md#omop-as-input).

!!! Question "More questions?"
    Pease take a look to our [Frequently Asked Questions](faq.md).

