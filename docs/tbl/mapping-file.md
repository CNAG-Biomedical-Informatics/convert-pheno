??? Question "What is a `Convert-Pheno` mapping file?"
    A mapping file is a text file in [YAML](https://en.wikipedia.org/wiki/YAML) format ([JSON](https://en.wikipedia.org/wiki/JSON) is also accepted) that connects a set of variables to a format that is understood by `Convert-Pheno`. This file maps your variables to the required **terms** of the [individuals](https://docs.genomebeacons.org/schemas-md/individuals_defaultSchema) entity from the Beacon v2 models, which serves a center model.

    ### Creating a mapping file

    To create a mapping file, start by reviewing the [example mapping file](https://github.com/cnag-biomedical-informatics/convert-pheno/blob/main/t/redcap2bff/in/redcap_mapping.yaml) provided with the installation. The goal is to replace the contents of such file with those from your REDCap project. The mapping file contains the following types of data:

    | Type        | Required (Optional)   | Required properties | Optional properties |
    | ----------- | ----------- | ------------------- | ------------------- |
    | Internal    | `project`   | `id, source, ontology, version` | ` description, baselineFieldsToPropagate` |
    | Beacon v2 terms   | `id, sex (diseases, exposures, info, interventionsOrProcedures, measures, phenotypicFeatures, treatments)` | `fields`| `age,ageOfOnset,assignTermIdFromHeader,bodySite,dateOfProcedure,dictionary,drugDose,drugUnit,duration,durationUnit,familyHistory,fields,mapping,procedureCodeLabel,selector,terminology,unit,visitId` |
    
    These are the properties needed to map your data to the entity `individuals` in the Beacon v2 Models:
    
    - **baselineFieldsToPropagate**, an array of columns containing measurements that were taken only at the initial time point (time = 0). Use this if you wish to duplicate these columns across subsequent rows for the same patient ID. It is important to ensure that the row containing baseline information appears first in the CSV.
    - **age**, a `string` representing the column that points to the age of the patient.
    - **ageOfOnset**, an `object` representing the column that points to the age at which the patient first experienced symptoms or was diagnosed with a condition.
    - **assignTermIdFromHeader**, an `array` for columns on which the ontology-term ids have to be assigned from the header.
    - **bodySite**, an `object` representing the column that points to the part of the body affected by a condition or where a procedure was performed.
    - **dateOfProcedure**, an `object` representing the column that points to when a procedure took place.
    - **dictionary**, is an `object` in the form of `key: value`. The `key` represents the original variable name in REDCap and the `value` represents the "phrase" that will be used to query a database to find an ontology candidate. For instance, you may have a variable named `cigarettes_days`, but you know that in [NCIt](https://www.ebi.ac.uk/ols/ontologies/ncit) the label is `Average Number Cigarettes Smoked a Day`. In this case, you will use `cigarettes_days: Average Number Cigarettes Smoked a Day`.
    - **drugDose**, an `object` representing the column that points to the dose column for each treatment.
    - **drugUnit**, an `object` representing the column that points to the unit column for each treatment.
    - **duration**, an `object` representing the column that points to the duration column for each treatment.
    - **durationUnit**, an `object` representing the column that points to the duration unit column for each treatment.
    - **familyHistory**, an `object` representing the column that points to the family medical history relevant to the patient's condition.
    - **fields**, can be either a `string` or an `array` consisting of the name of the REDCap variables that map to that Beacon v2 term.
    - **mapping**, is an `object` in the form of `key: value` that we use to map our Beacon v2 objects to REDCap variables.
    - **procedureCodeLabel** , a nested `object` with specific mappings for `interventionsOrProcedures`.
    - **ontology**, it's an `string` to define more granularly the ontology for this particular Beacon v2 term. If not present, the script will use that from `project.ontology`.
    - **routeOfAdministration**, a nested `object` with specific mappings for `treatments`.
    - **selector**, a nested `object` value with specific mappings.
    - **terminology**, a nested `object` value with user-defined ontology terms.

    ??? Example "Terminology example"
        ```yaml
        terminology:
          My fav term:
            id: FOO:12345678
        label: Label for my fav term
        ```
    
    - **unit**, an `object` representing the column that points to the unit of measurement for a given value or treatment.
    - **visitId**, the column with visit occurrence id.
    
    ??? Tip "Defining the values in the property `dictionary`"
        Before assigning values to `dictionary` it's important that you think about which ontologies/terminologies you want to use. The field `project.ontology` defines the ontology for the whole project, but you can also specify a another antology at the Beacon v2 term level. Once you know which ontologies to use, then try searching for such term to get an accorate label for it. For example, if you have chosen `ncit`, you can search for the values within NCIt at [EBI Search](https://www.ebi.ac.uk/ols/ontologies/ncit). `Convert-Pheno` will use these values to retrieve the actual ontology term from its internal databases.
