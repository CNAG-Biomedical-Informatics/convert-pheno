!!! Tip "Google Colab version"
    We created a [Google Colab version](https://colab.research.google.com/drive/1T6F3bLwfZyiYKD6fl1CIxs9vG068RHQ6) of the tutorial. Users can view notebooks shared publicly without sign-in, but you need a google account to execute code.

    We also have a local copy of the notebook that can be downloaded from the [repo](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/nb/convert_pheno_cli_tutorial.ipynb). 

This page provides brief tutorials on how to perform data conversion by using `Convert-Pheno`**command-line interface**.

!!! Info "Note on installation"
    Before proceeding, ensure that the software is properly installed. In the following instructions, it will be assumed that you have downloaded and installed the [containerized version](https://github.com/CNAG-Biomedical-Informatics/convert-pheno#containerized-recommended-method).

### How to convert:

=== "REDCap to Phenopackets v2"

    This section provides a summary of the steps to convert a REDCap project to Phenopackets v2. 

    * The starting point is to log in to your REDCap system and export the data to CSV format. If you need more information on REDCap, we recommend consulting the comprehensive [documentation](https://confluence.research.cchmc.org/display/CCTSTRED/Cincinnati+REDCap+Resource+Center) provided by the Cincinnati Children's Hospital Medical Center.

    * After exporting the data, you must also download the REDCap dictionary in CSV format. This can be done within REDCap by navigating to `Project Setup/Data Dictionary/Download the current`.

    * Since REDCap projects are "free-format," a mapping file is necessary to connect REDCap project variables (i.e. fields) to something meaningful for `Convert-Pheno`. This mapping file will be used in the conversion process.

    !!! Question "What is a `Convert-Pheno` mapping file?"
        A mapping file is a text file in [YAML](https://en.wikipedia.org/wiki/YAML) format ([JSON]((https://en.wikipedia.org/wiki/JSON) is also accepted) that connects a set of variables to a format that is understood by `Convert-Pheno`. This file maps your variables to the required **terms** of the [individuals](https://docs.genomebeacons.org/schemas-md/individuals_defaultSchema) entity from the Beacon v2 models, which serves a center model.

    ### Creating a mapping file

    To create a mapping file, start by reviewing the [example mapping file](https://github.com/cnag-biomedical-informatics/convert-pheno/blob/main/t/redcap2bff/in/redcap_mapping.yaml) provided with the installation. The goal is to replace the contents of such file with those from your REDCap project. The mapping file contains the following types of data:

    | Type        | Required    | Required properties | Optional properties |
    | ----------- | ----------- | ------------------- | ------------------- |
    | Internal    | `project`   | `id, source, ontology` | ` description` |
    | Beacon v2 terms   | `diseases, exposures, id, info, interventionsOrProcedures, measures, phenotypicFeatures, sex, treatments` | `fields`| `dict, map, radio, ontology, routesOfAdministration` |

     * These are the properties needeed to map your data to the entity `individuals` in the Beacon v2 Models:
        - **fields**, is an `array` consisting of the name of the REDCap variables that map to that Beacon v2 term.
        - **map**, is an `object` in the form of `key: value` that we use to map our Beacon v2 objects to REDCap variables. For instance, you may have a field named `age_first_diagnosis` that it's called `ageOgOnset` on Beacon v2. In this case you will use `ageOfOnset: age_first_diagnosis`.
        - **dict**, is an `object` in the form of `key: value`. The `key` represents the original variable name in REDCap and the `value` represents the "phrase" that will be used to query a database to find an ontology candidate. For instance, you may have a variable named `cigarettes_days`, but you know that in [NCIT](https://www.ebi.ac.uk/ols/ontologies/ncit) the label is `Average Number Cigarettes Smoked a Day`. In this case you will use `cigarettes_days: Average Number Cigarettes Smoked a Day`.
        - **radio**, a nested `object` value with specific mappings.
        - **ontology**, it's an string to define more granularly the ontology for this particular Beacon v2 term. If not present, the script will use that from `project.ontology`.
        - **routesOfAdministration**, an `array` with specific mappings for `treatments`.

    !!! Tip "Defining the values in the property `dict`"
        Before assigning values to `dict` it's important that you think about which ontologies you want to use. The field `project.ontology` defines the ontology for the whole project, but you can also specify a another antology at the Beacon v2 term level. Once you know which ontologies to use, then try searching for such term to get an accorate label for it. For example, if you have chosen `ncit`, you can search for the values within NCIT at [EBI Search](https://www.ebi.ac.uk/ols/ontologies/ncit). `Convert-Pheno` will use these values to retrieve the actual ontology from its internal databases.

    !!! Warning "About text similarity in database searches"
        `Convert-Pheno` comes with a few pre-configured databases and it will search for ontologies there. Two two types of searches can be performed:

         1. `exact` (default)

             Retrieves only exact matches for a specified 'label'

         2. `mixed` (needs `--search mixed`)

             The script will begin by attempting an exact match for 'label', and if it is unsuccessful, it will then conduct a search based on string (phrase) similarity and select the ontology with the highest score. 
         Example (NCIT ontology): 

          Search phrase: **Exercise pain management** with `exact` search.

          - exact match: Exercise Pain Management

          Search phrase: **Brain Hemorrhage** with `mixed` search.

          - exact match: NA

          - similarity match: Intraventricular Brain Hemorrhage

          `--min-text-similarity-score` sets the minimum value for the Cosine / Sorensen-Dice coefficient. The default value (0.8) is very conservative.

         Note that `mixed` search requires more computational time and its results can be unpredictable. Please use it with caution.

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

    In a partial export, many ontologies may be missing from the `CONCEPT` table, as a result, `Convert-Pheno` will perform a search on the included **ATHENA-OHDSI** database. To enable this search you should use the flag `--ohdsi-db`.

    ### Running `Convert-Pheno`

    Once you have created the mapping file you can proceed to run `convert-pheno` with the **command-line interface**. Please see how [here](omop-cdm.md#omop-as-input).

!!! Question "More questions?"
    Please take a look to our [Frequently Asked Questions](faq.md).

