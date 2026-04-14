??? Question "What is a `Convert-Pheno` mapping file?"
    A mapping file is a text file in [YAML](https://en.wikipedia.org/wiki/YAML) format ([JSON](https://en.wikipedia.org/wiki/JSON) is also accepted) that connects a set of variables to a format that is understood by `Convert-Pheno`.

    In `v0.30`, the layout is entity-aware:

    - `project` holds project-level metadata.
    - `beacon` groups Beacon entities at the same level.
    - `beacon.individuals` holds the semantic mapping rules to the [individuals](https://docs.genomebeacons.org/schemas-md/individuals_defaultSchema) entity from the Beacon v2 models, which remains the central normalized model for mapping-file based conversions.
    - `beacon.datasets`, `beacon.cohorts`, and `beacon.biosamples` hold optional metadata/defaults for emitted Beacon entities.

    The `beacon.individuals` wrapper is mandatory in `v0.30`.

    ### Mental model

    A mapping section inside `beacon.individuals`, such as `diseases`, `exposures`, or `treatments`, usually answers four different questions:

    1. Which source columns participate?
       Use `fields`.
    2. If the source field name is not the ontology label, what field-level term should be searched?
       Use `fieldTermLabels`.
    3. If the recorded value is not the ontology label, what value-level term should be searched?
       Use `valueTermLabels`.
    4. If extra target-side attributes are needed, where do they come from?
       Use `targetFields` for simple target attributes and `fieldRules` for per-field nested rules.

    In practice:

    - `fieldTermLabels` describes the meaning of the **column/header itself**.
    - `valueTermLabels` describes the meaning of the **recorded cell value**.
    - `targetFields` points to source columns used to populate target-side attributes such as `primaryKey`, `age`, or `date`.
    - `fieldRules` holds field-specific nested configuration, for example value-to-term rules or auxiliary pointers such as `ageAtExposure`.

    ### Creating a mapping file

    To create a mapping file, start by reviewing the [example mapping file](https://github.com/cnag-biomedical-informatics/convert-pheno/blob/main/t/redcap2bff/in/redcap_mapping.yaml) provided with the installation. The goal is to replace the contents of such file with those from your REDCap project. The mapping file contains the following types of data:

    ??? Example "Minimal mapping skeleton"
        ```yaml
        project:
          id: my_project
          source: redcap
          ontology: ncit
          version: 0.1

        beacon:
          datasets:
            id: my-project-dataset
            name: My Project Dataset
          cohorts:
            id: my-project-cohort
            name: My Project Cohort
            cohortType: study-defined
          individuals:
            id:
              fields: [record_id, visit_name]
              targetFields:
                primaryKey: record_id

            sex:
              fields: sex
              valueTermLabels:
                Male: Male
                Female: Female

            diseases:
              fields: [diagnosis]
              valueTermLabels:
                UC: Ulcerative Colitis
                CD: Crohn Disease

            exposures:
              fields: [smoking]
              fieldTermLabels:
                smoking: Smoking
              valueTermLabels:
                Current smoker: Current Smoker
                Ex-smoker: Former Smoker
                Never smoked: Never Smoker

            info:
              fields: [record_id, age, visit_name]
              targetFields:
                age: age
        ```

        This skeleton shows the minimum structure most users need first:

        - `project` defines the source and default ontology.
        - `beacon` groups all Beacon entity sections in one place.
        - `beacon.individuals` contains the semantic mapping for the Beacon `individuals` entity.
        - `beacon.individuals.id.targetFields.primaryKey` points to the source column used as the main individual identifier.
        - `fieldTermLabels` maps the meaning of a **column/header**.
        - `valueTermLabels` maps the meaning of a **recorded cell value**.
        - `targetFields` maps extra target-side attributes such as `age`.

    | Type        | Required (Optional)   | Required properties | Optional properties |
    | ----------- | ----------- | ------------------- | ------------------- |
    | Internal    | `project`   | `id, source, ontology, version` | `description, baselineFieldsToPropagate` |
    | Beacon entities | `beacon` | `individuals` | `datasets, cohorts, biosamples` |
    | Entity mapping   | `beacon.individuals` | `id, sex` | `diseases, exposures, info, interventionsOrProcedures, measures, phenotypicFeatures, treatments, ethnicity, geographicOrigin, karyotypicSex, pedigrees` |
    
    These are the properties needed to map your data to the entity `individuals` in the Beacon v2 Models:

    - **beacon.individuals**, an `object` containing the semantic mapping rules for the Beacon `individuals` entity.
    - **beacon**, a top-level `object` with the entity sections. Use `beacon.datasets` and `beacon.cohorts` to override synthesized metadata such as `id`, `name`, `description`, `externalUrl`, `cohortType`, or `cohortDataTypes`. These values are merged with the tool-generated defaults.
    
    - **baselineFieldsToPropagate**, an array of columns containing measurements that were taken only at the initial time point (time = 0). Use this if you wish to duplicate these columns across subsequent rows for the same patient ID. It is important to ensure that the row containing baseline information appears first in the CSV.
    - **age**, a `string` representing the column that points to the age of the patient.
    - **ageAtProcedure**, an `object` representing the column that points to the age when a procedure took place.
    - **ageOfOnset**, an `object` representing the column that points to the age at which the patient first experienced symptoms or was diagnosed with a condition.
    - **bodySite**, an `object` representing the column that points to the part of the body affected by a condition or where a procedure was performed.
    - **dateOfProcedure**, an `object` representing the column that points to when a procedure took place.
    - **drugDose**, an `object` representing the column that points to the dose column for each treatment.
    - **drugUnit**, an `object` representing the column that points to the unit column for each treatment.
    - **duration**, an `object` representing the column that points to the duration column for each treatment.
    - **durationUnit**, an `object` representing the column that points to the duration unit column for each treatment.
    - **familyHistory**, an `object` representing the column that points to the family medical history relevant to the patient's condition.
    - **fieldRules**, a nested `object` with per-field rules such as value-to-term mappings or auxiliary field configuration like `ageAtExposure`. Use this when a single Beacon term needs field-specific behavior rather than one global rule.
    - **fieldTermLabels**, is an `object` in the form of `key: value`. The `key` represents the original variable or header name and the `value` represents the ontology query phrase used for the field itself. Use this when the **column name** carries the term meaning. For instance, you may have a variable named `cigarettes_days`, but you know that in [NCIt](https://www.ebi.ac.uk/ols/ontologies/ncit) the label is `Average Number Cigarettes Smoked a Day`. In this case, you will use `cigarettes_days: Average Number Cigarettes Smoked a Day`.
    - **fields**, can be either a `string` or an `array` consisting of the name of the source variables that map to that Beacon v2 term.
    - **procedureCodeLabel** , a nested `object` with specific mappings for `interventionsOrProcedures`.
    - **ontology**, it's an `string` to define more granularly the ontology for this particular Beacon v2 term. If not present, the script will use that from `project.ontology`.
    - **routeOfAdministration**, a nested `object` with specific mappings for `treatments`.
    - **targetFields**, is an `object` in the form of `key: value` that maps target-side attributes such as `primaryKey`, `age`, `date`, or `duration` to source columns. Use this when the target model expects a named attribute that is not itself an ontology lookup.
    - **terminology**, a nested `object` value with user-defined ontology terms. Use this when you already know the exact ontology object and want to bypass database lookup for that term.
    - **useHeaderAsTermLabel**, an `array` for columns on which the ontology-term labels have to be assigned from the header instead of the recorded value. This is common for checkbox-like columns where the header says the term and the cell only says whether it is present.

    ??? Example "Terminology example"
        ```yaml
        terminology:
          My fav term:
            id: FOO:12345678
        label: Label for my fav term
        ```
    
    - **unit**, an `object` representing the column that points to the unit of measurement for a given value or treatment.
    - **valueTermLabels**, is an `object` in the form of `key: value` where the `key` is the original recorded value and the `value` is the ontology query phrase used to map that value. Use this when the **cell value** carries the term meaning, for example `Current smoker -> Current Smoker`.
    - **visitId**, the column with visit occurrence id.

    ??? Example "Field vs value mapping"
        ```yaml
        exposures:
          fields: [smoking, cigarettes_days]
          fieldTermLabels:
            smoking: Smoking
            cigarettes_days: Average Number Cigarettes Smoked a Day
          valueTermLabels:
            Current smoker: Current Smoker
            Ex-smoker: Former Smoker
            Never smoked: Never Smoker
        ```

        In this example:

        - `smoking -> Smoking` comes from the **field/header**, so it belongs in `fieldTermLabels`.
        - `Current smoker -> Current Smoker` comes from the **recorded value**, so it belongs in `valueTermLabels`.

    ??? Tip "Defining the values in `fieldTermLabels` and `valueTermLabels`"
        Before assigning values to `fieldTermLabels` or `valueTermLabels` it's important that you think about which ontologies or terminologies you want to use. The field `project.ontology` defines the ontology for the whole project, but you can also specify another ontology at the Beacon v2 term level. Once you know which ontologies to use, search for accurate labels first. For example, if you have chosen `ncit`, you can search for the values within NCIt at [EBI Search](https://www.ebi.ac.uk/ols/ontologies/ncit). `Convert-Pheno` will use these values to retrieve the actual ontology term from its internal databases.
