---
title: Tutorial
sidebar_label: Tutorial
---

This page gives **short walkthroughs** for three common `convert-pheno` conversions.

:::tip[Google Colab version]
A runnable notebook version is available in [Google Colab](https://colab.research.google.com/drive/1T6F3bLwfZyiYKD6fl1CIxs9vG068RHQ6). A local copy is also available in the [repo](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/nb/convert_pheno_cli_tutorial.ipynb).

:::
:::note[Before you start]
These examples assume that `Convert-Pheno` is already installed. If not, start with [Download & Installation](download-and-installation).

:::
## Choose a Walkthrough

| Goal | Start Here |
|------|------------|
| I have a REDCap export and want Phenopackets | [REDCap to PXF](#redcap-to-pxf) |
| I have OMOP-CDM data and want BFF | [OMOP CDM to BFF](#omop-cdm-to-bff) |
| I have a plain CSV and a mapping file | [CSV to BFF](#csv-to-bff) |

For short copy-paste commands without tutorial context, use [Conversion Recipes](conversion-recipes).

## REDCap to PXF

This is a good route when you have a **REDCap export** and want to produce **Phenopackets**.

You will usually need three files:

1. REDCap data export in CSV format
2. REDCap data dictionary in CSV format
3. Mapping file in YAML or JSON format

Because REDCap projects are **free-form**, the mapping file is what tells `Convert-Pheno` how your project variables should be interpreted.

<details>
<summary>What is a `Convert-Pheno` mapping file?</summary>

A mapping file is a text file in [YAML](https://en.wikipedia.org/wiki/YAML) format ([JSON](https://en.wikipedia.org/wiki/JSON) is also accepted) that connects a set of variables to a format that is understood by `Convert-Pheno`.

In `v0.30`, the layout is entity-aware:

- `project` holds project-level metadata.
- `beacon` groups Beacon entities at the same level.
- `beacon.individuals` holds the semantic mapping rules to the [individuals](https://docs.genomebeacons.org/schemas-md/individuals_defaultSchema) entity from the Beacon v2 models, which remains the central normalized model for mapping-file based conversions.
- `beacon.datasets`, `beacon.cohorts`, and `beacon.biosamples` hold optional metadata/defaults for emitted Beacon entities.
- These metadata overrides are currently consumed only by the conversion routes that use a mapping file: `csv2bff`, `redcap2bff`, and `cdisc2bff`.

The `beacon.individuals` wrapper is mandatory in `v0.30`.

**Mental model**

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

**Creating a mapping file**

To create a mapping file, start by reviewing the [example mapping file](https://github.com/cnag-biomedical-informatics/convert-pheno/blob/main/t/redcap2bff/in/redcap_mapping.yaml) provided with the installation. The goal is to replace the contents of such file with those from your REDCap project. The mapping file contains the following types of data:

    <details>
    <summary>Minimal mapping skeleton</summary>

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

    </details>
| Type        | Required (Optional)   | Required properties | Optional properties |
| ----------- | ----------- | ------------------- | ------------------- |
| Internal    | `project`   | `id, source, ontology, version` | `description, baselineFieldsToPropagate` |
| Beacon entities | `beacon` | `individuals` | `datasets, cohorts, biosamples` |
| Entity mapping   | `beacon.individuals` | `id, sex` | `diseases, exposures, info, interventionsOrProcedures, measures, phenotypicFeatures, treatments, ethnicity, geographicOrigin, karyotypicSex, pedigrees` |

These are the properties needed to map your data to the entity `individuals` in the Beacon v2 Models:

- **beacon.individuals**, an `object` containing the semantic mapping rules for the Beacon `individuals` entity.
- **beacon**, a top-level `object` with the entity sections. Use `beacon.datasets` and `beacon.cohorts` to override synthesized metadata such as `id`, `name`, `description`, `externalUrl`, `cohortType`, or `cohortDataTypes`. These values are merged with the tool-generated defaults. This augmentation currently applies only to `csv2bff`, `redcap2bff`, and `cdisc2bff`.

- **baselineFieldsToPropagate**, an array of columns containing measurements that were taken only at the initial time point (time = 0). Use this if you wish to duplicate these columns across subsequent rows for the same patient ID. It is important to ensure that the row containing baseline information appears first in the CSV.
- Mapping-file conversions preserve a raw source-row snapshot in the generated `BFF` `info` object by default, such as `CSV_columns` or `REDCap_columns`. This helps users audit mapped values against the input file. Use `--no-source-info` to omit these copied source payloads.
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

    <details>
    <summary>Terminology example</summary>

    ```yaml
        terminology:
          My fav term:
            id: FOO:12345678
        label: Label for my fav term
        ```
    
    </details>
- **unit**, an `object` representing the column that points to the unit of measurement for a given value or treatment.
- **valueTermLabels**, is an `object` in the form of `key: value` where the `key` is the original recorded value and the `value` is the ontology query phrase used to map that value. Use this when the **cell value** carries the term meaning, for example `Current smoker -> Current Smoker`.
- **visitId**, the column with visit occurrence id.

    <details>
    <summary>Field vs value mapping</summary>

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

    </details>
    <details>
    <summary>Defining the values in `fieldTermLabels` and `valueTermLabels`</summary>

    Before assigning values to `fieldTermLabels` or `valueTermLabels` it's important that you think about which ontologies or terminologies you want to use. The field `project.ontology` defines the ontology for the whole project, but you can also specify another ontology at the Beacon v2 term level. Once you know which ontologies to use, search for accurate labels first. For example, if you have chosen `ncit`, you can search for the values within NCIt at [EBI Search](https://www.ebi.ac.uk/ols/ontologies/ncit). `Convert-Pheno` will use these values to retrieve the actual ontology term from its internal databases.

    </details>
</details>
For **mapping-file-based conversions**, `Convert-Pheno` can also use similarity-based lookup to help connect source fields to target terms:

<details>
<summary>About text similarity in database searches</summary>


`Convert-Pheno` comes with several pre-configured ontology/terminology databases. It supports three types of label-based search strategies:

---

#### 1. `exact` (default)

Returns only **exact matches** for the given label string. If the label is not found exactly, no results are returned.

---

#### 2. `mixed` (use `--search mixed`)

**Hybrid search**: First tries to find an exact label match. If none is found, it performs a token-based similarity search and returns the closest matching concept based on the **highest similarity score**.

---

#### 3. ✨ `fuzzy` (use `--search fuzzy`)

**Hybrid search with fuzzy ranking**:  
Like `mixed`, it starts with an exact match attempt. If that fails, it performs a **weighted similarity search**, where:
- **90%** of the score comes from token-based similarity (e.g., cosine or Dice coefficient),
- **10%** comes from the **normalized Levenshtein similarity**.

The concept with the highest composite score is returned.

**Note:** The normalized Levenshtein similarity is computed on top of the candidate results produced by the full text search. In this approach, an initial full text search (using token-based methods) returns a set of potential matches. The fuzzy search then refines these results by applying the normalized Levenshtein distance to better handle minor typographical differences, ensuring that the final composite score reflects both overall token similarity and fine-grained character-level differences.


---

#### 🔍 Example Search Behavior

**Query:** `Exercise pain management`  
- With `--search exact`: ✅ Match found — **Exercise Pain Management**

**Query:** `Brain Hemorrhage`  
- With `--search mixed`:  
  - ❌ No exact match  
  - ✅ Closest match by similarity: **Intraventricular Brain Hemorrhage**

---

**Similarity threshold**

The `--min-text-similarity-score` option sets the minimum threshold for `mixed` and `fuzzy` searches.
- Default: `0.8` (conservative)  
- Lowering the threshold may increase recall but may introduce irrelevant matches.

---

**Performance note**

Both `mixed` and `fuzzy` modes are more computationally intensive and can produce unexpected or less interpretable matches. Use them with care, especially on large datasets.

---

**Example results table**

Below is an example showing how the query `Sudden Death Syndrome` performs using different search modes against the NCIt ontology:

| Query                 | Search | NCIt match (label)                                    | NCIt code    | Cosine | Dice | Levenshtein (Normalized) | Composite |
|-----------------------|--------|-------------------------------------------------------|--------------|--------|------|--------------------------|-----------|
| Sudden Death Syndrome | exact  | NA                                                    | NA           | NA     | NA   | NA                       | NA        |
|                       | mixed  | CDISC SDTM Sudden Death Syndrome Type Terminology     | NCIT:C101852 | 0.65   | 0.60 | NA                       | NA        |
|                       |        | Family History of Sudden Arrythmia Death Syndrome     | NCIT:C168019 | 0.65   | 0.60 | NA                       | NA        |
|                       |        | Family History of Sudden Infant Death Syndrome        | NCIT:C168209 | 0.65   | 0.60 | NA                       | NA        |
|                       |        | Sudden Infant Death Syndrome                          | NCIT:C85173  | 0.86   | 0.86 | NA                       | NA        |
|                       | ✨ fuzzy  | CDISC SDTM Sudden Death Syndrome Type Terminology     | NCIT:C101852 | 0.65   | 0.60 | 0.43                     | 0.63      |
|                       |        | Family History of Sudden Arrythmia Death Syndrome     | NCIT:C168019 | 0.65   | 0.60 | 0.43                     | 0.63      |
|                       |        | Family History of Sudden Infant Death Syndrome        | NCIT:C168209 | 0.65   | 0.60 | 0.46                     | 0.63      |
|                       |        | Sudden Infant Death Syndrome                          | NCIT:C85173  | 0.86   | 0.86 | 0.75                     | 0.85      |

**Interpretation:**  

- With `exact`, there are no matches.

- With `mixed`, the best match will be `Sudden Infant Death Syndrome`.

- With `fuzzy`, the **composite score** (90% token-based + 10% Levenshtein similarity) is used to rank results.  
  The highest match is `Sudden Infant Death Syndrome`, with a composite score of **0.85**.

---

✨ Now we introduce a typo on the query `Sudden Infant Deth Syndrome`:


| Query                 | Mode  | Candidate Label                                       | Code         | Cosine | Dice   |  Levenshtein (Normalized) | Composite |
|-----------------------|-------|-------------------------------------------------------|-------------|--------|--------|------------|-----------|
| Sudden Infant Deth Syndrome | fuzzy | CDISC SDTM Sudden Death Syndrome Type Terminology     | NCIT:C101852 | 0.38   | 0.36   | 0.33        | 0.37      |
|                             |       | Family History of Sudden Arrythmia Death Syndrome     | NCIT:C168019 | 0.38   | 0.36   | 0.43        | 0.38      |
|                             |       | Family History of Sudden Infant Death Syndrome        | NCIT:C168209 | 0.57   | 0.55   | 0.59        | 0.57      |
|                             |       | Sudden Infant Death Syndrome                          | NCIT:C85173 | 0.75   | 0.75   | 0.96        | 0.77      

To capture the best match we would need to lower the threshold to  `--min-text-similarity-score 0.75`

It is possible to change the weight of Levenshtein similarity via `--levenshtein-weight <floating 0.0 - 1.0>`.


</details>
<details>
<summary>Composite Similarity Score</summary>


The composite similarity score is computed as a weighted sum of two measures: the token-based similarity and the normalized Levenshtein similarity.

#### 1. Token-Based Similarity

This is calculated using methods like cosine or Dice similarity to measure how similar the tokens (words) of two strings are.

#### 2. Normalized Levenshtein Similarity

The normalized Levenshtein similarity is defined as:

```text
\text{NormalizedLevenshtein}(s_1, s_2) = 1 - \frac{\text{lev}(s_1, s_2)}{\max(|s_1|, |s_2|)}
```

Where:
- `\text{lev}(s_1, s_2)` is the Levenshtein edit distance—the minimum number of insertions, deletions, or substitutions required to change `s_1` into `s_2`.
- `|s_1|` and `|s_2|` are the lengths of the strings `s_1` and `s_2`, respectively.

This formula produces a score between 0 and 1, with **1.0** meaning identical strings and **0.0** meaning completely different strings.

#### 3. Composite Score Formula

The final composite similarity score `C` is a weighted combination of the two metrics:

```text
C(s_1, s_2) = \alpha \cdot \text{TokenSimilarity}(s_1, s_2) + \beta \cdot \text{NormalizedLevenshtein}(s_1, s_2)
```

Where:
- `\alpha` (or `token_weight`) is the weight assigned to the token-based similarity.
- `\beta` (or `lev_weight`) is the weight assigned to the normalized Levenshtein similarity.

A common default is to set `\alpha = 0.9` and `\beta = 0.1`, emphasizing the token-based similarity. However, for short strings (4–5 words), you might consider adjusting the balance (for example, `\alpha = 0.95` and `\beta = 0.05`) if small typographical differences are less critical.

</details>
Run the conversion:

```bash
convert-pheno -iredcap redcap.csv \
  --redcap-dictionary dictionary.csv \
  --mapping-file mapping.yaml \
  -opxf phenopackets.json
```

If you need more detail about REDCap-specific behavior, see [REDCap](redcap).

## OMOP CDM to BFF

This route is meant for **OMOP exports** in SQL or CSV form.

Two situations are common:

1. Full export: the `CONCEPT` table already contains the standardized terms needed for conversion
2. Partial export: some terms are missing, so `Convert-Pheno` needs the bundled ATHENA-OHDSI lookup database and the `--ohdsi-db` flag

For smaller inputs:

```bash
convert-pheno -iomop omop.sql -obff individuals.json
```

For larger inputs:

```bash
convert-pheno -iomop omop.sql.gz -obff individuals.json.gz --stream --ohdsi-db
```

If you are working with OMOP regularly, see [OMOP-CDM](omop-cdm) for the fuller explanation of SQL, CSV, `CONCEPT`, and streaming behavior.

If you want entity-aware `BFF` output instead of the individuals-only `individuals.json` path, request the entities explicitly:

```bash
convert-pheno -iomop PERSON.csv CONCEPT.csv DRUG_EXPOSURE.csv \
  -obff \
  --entities individuals datasets cohorts \
  --out-dir out/
```

In mapping-file conversions, the top-level `beacon` section can override synthesized `datasets` and `cohorts` metadata. This currently applies to `csv2bff`, `redcap2bff`, and `cdisc2bff`, which are the routes that use a mapping file.

## CSV to BFF

This route is intended for **raw clinical CSV data** that does not already follow one of the supported data models.

As with REDCap, the key requirement is a mapping file. The mapping-file structure is the same as the one shown in [REDCap to PXF](#redcap-to-pxf): source columns are described under `beacon.individuals`, while optional `beacon.datasets`, `beacon.cohorts`, and `beacon.biosamples` sections can provide entity metadata for routes that support it.

For the complete mapping-file model, see [Mapping Steps](mapping-steps). For ontology lookup modes and thresholds, see [DB Search](tbl/db-search).

Run the conversion:

```bash
convert-pheno -icsv clinical_data.csv \
  --mapping-file clinical_data_mapping.yaml \
  -obff individuals.json
```

If your separator is not the default one expected by the tool, add `--sep`.

If you want `datasets` and `cohorts` as well, switch to entity mode:

```bash
convert-pheno -icsv clinical_data.csv \
  --mapping-file clinical_data_mapping.yaml \
  -obff \
  --entities individuals datasets cohorts \
  --out-dir out/
```

## Need more detail?

- [Usage](usage) for more command examples
- [CSV](csv) for raw CSV input
- [REDCap](redcap) for REDCap exports
- [OMOP-CDM](omop-cdm) for OMOP-specific options and caveats
- [FAQ](faq) for common questions
