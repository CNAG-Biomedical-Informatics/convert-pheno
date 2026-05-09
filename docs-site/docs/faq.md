---
title: FAQs
sidebar_label: FAQs
---

# FAQs

## General

<details>
<summary>What does `Convert-Pheno` do?</summary>


`Convert-Pheno` is an open-source toolkit for converting clinical and phenotypic data between supported exchange models such as `BFF`, `PXF`, `OMOP-CDM`, `REDCap`, `CDISC-ODM`, and mapped `CSV`.


</details>
<details>
<summary>Is `Convert-Pheno` free?</summary>


Yes. See the [license](https://github.com/mrueda/convert-pheno/blob/main/LICENSE).


</details>
<details>
<summary>Is `Convert-Pheno` or `Pheno-Convert`?</summary>


It's **`Convert-Pheno`**, for two reasons:

1. The naming is inspired by the `convert` utility from [ImageMagick](https://imagemagick.org).
2. In related contexts, people refer to *PhenoConvert* as in [PhenoCopy](https://en.wikipedia.org/wiki/Phenocopy) or [PhenoConversion](https://www.universiteitleiden.nl/en/research/research-projects/science/phenoconversion).


</details>
<details>
<summary>Is `Convert-Pheno` ready for use in production environments?</summary>

The software is fully functional and has been successfully used in several European-funded projects. However, it is still in beta, so ongoing improvements and refinements are to be expected.


</details>
<details>
<summary>If I use `Convert-Pheno` to convert my data to [Beacon v2 Models](bff), does this mean I have a Beacon v2?</summary>


No. Beacon v2 is an [API specification](https://docs.genomebeacons.org), while the [Beacon v2 Models](bff) are the data models used by that API. `Convert-Pheno` helps generate compatible data files, but a working Beacon still needs storage and an API layer on top.


</details>
<details>
<summary>What is the difference between Beacon v2 Models and Beacon v2?</summary>


**Beacon v2** is a specification to build an [API](https://docs.genomebeacons.org). The [Beacon v2 Models](https://docs.genomebeacons.org/models/) define the format for the API's responses to queries regarding biological data. With the help of `Convert-Pheno`, data exchange text files ([BFF](bff)) that align with this response format can be generated. By doing so, the BFF files can be integrated into a non-SQL database, such as MongoDB, without the API having to perform any additional data transformations internally.


</details>
<details>
<summary>Why are there so many clinical data standards?</summary>


Different standards solve different problems: clinical care, research harmonization, case reporting, API exchange, or project-level data capture. `Convert-Pheno` exists because those formats overlap in practice, but they were not designed as one unified ecosystem.


</details>
<details>
<summary>Are you planning in supporting other clinical data formats?</summary>


Afirmative, but it will depend on community adoption. Please check our [roadmap](future-plans) for more information.


</details>
<details>
<summary>Are longitudinal data supported?</summary>


Although Beacon v2 and Phenopackets v2 allow for storing time information in some properties, there is currently no way to associate medical visits to properties. To address this:

* `omop2bff` -  we added an _ad hoc_ property (**_visit**) to store medical visit information for longitudinal events in variables that have it (e.g., measures, observations, etc.).

* `redcap2bff` - In REDCap, visit/event information is not stored at the record level. We added this information inside `info` property.

We raised this issue to the respective communities in the hope of a more permanent solution.


</details>
<details>
<summary>What is an "ontology" in Beacon v2 and Phenopacket v2 context?</summary>

In this context, “ontology” is used broadly for standardized identifiers such as HPO, NCIt, LOINC, or RxNorm terms. In practice, these are the coded terms used in the JSON structures handled by Beacon v2 and Phenopackets.

</details>

<details>
<summary>I have a collection of PXF files encoded using HPO and ICD-10 terms, and I need to convert them to BFF format, but encoded in OMIM and SNOMED-CT terminologies. Can you assist me with this?</summary>


Not directly. `Convert-Pheno` converts data models, but it does not rewrite source ontology terms into a different terminology system. If you need ontology remapping, that should be handled as a separate mapping step.



</details>
<details>
<summary>What type of data validation is carried out?</summary>

Convert-Pheno uses external validators during development where practical: `bff-tools validate` from [beacon2-cbi-tools](https://github.com/CNAG-Biomedical-Informatics/beacon2-cbi-tools) for Beacon/BFF output, the extended `xt/protobuff.t` protobuf parsing test for PXF output, and [omop-csv-validator](https://github.com/CNAG-Biomedical-Informatics/omop-csv-validator) for OMOP CSV output. For BFF mappings, validator failures are used to refine runtime mappings, defaults, and type coercions until generated entity files validate against the Beacon v2 schemas.

Convert-Pheno does **not** validate the clinical correctness or completeness of your input data. Source files should be checked before conversion.

See [Output Validation](output-validation) for details.
</details>
<details>
<summary>What type of **database search** is carried out?</summary>


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
    
    ### 💡 Similarity Threshold
    
    The `--min-text-similarity-score` option sets the minimum threshold for `mixed` and `fuzzy` searches.
    - Default: `0.8` (conservative)  
    - Lowering the threshold may increase recall but may introduce irrelevant matches.
    
    ---
    
    ### ⚠️ Performance Note
    
    Both `mixed` and `fuzzy` modes are more computationally intensive and can produce unexpected or less interpretable matches. Use them with care, especially on large datasets.
    
    ---
    
    ### 🧪 Example Results Table
    
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
    
    $$
    \text{NormalizedLevenshtein}(s_1, s_2) = 1 - \frac{\text{lev}(s_1, s_2)}{\max(|s_1|, |s_2|)}
    $$
    
    Where:
    - `\text{lev}(s_1, s_2)` is the Levenshtein edit distance—the minimum number of insertions, deletions, or substitutions required to change `s_1` into `s_2`.
    - `|s_1|` and `|s_2|` are the lengths of the strings `s_1` and `s_2`, respectively.
    
    This formula produces a score between 0 and 1, with **1.0** meaning identical strings and **0.0** meaning completely different strings.
    
    #### 3. Composite Score Formula
    
    The final composite similarity score `C` is a weighted combination of the two metrics:
    
    $$
    C(s_1, s_2) = \alpha \cdot \text{TokenSimilarity}(s_1, s_2) + \beta \cdot \text{NormalizedLevenshtein}(s_1, s_2)
    $$
    
    Where:
    - `\alpha` (or `token_weight`) is the weight assigned to the token-based similarity.
    - `\beta` (or `lev_weight`) is the weight assigned to the normalized Levenshtein similarity.
    
    A common default is to set `\alpha = 0.9` and `\beta = 0.1`, emphasizing the token-based similarity. However, for short strings (4–5 words), you might consider adjusting the balance (for example, `\alpha = 0.95` and `\beta = 0.05`) if small typographical differences are less critical.


    </details>
</details>
<details>
<summary>Error Handling for `CSV_XS ERROR: 2023 - EIQ - QUO character not allowed @ rec 1 pos 21 field 1`</summary>


This usually means the file separator does not match what `Convert-Pheno` is expecting. See [Troubleshooting](troubleshooting#csv_xs-separator-error).


</details>
<details>
<summary>Should I export my REDCap project as _raw data_ or as _labels_ for use with `Convert-Pheno`?</summary>


Prefer **raw data** together with the REDCap dictionary file. If your export uses labels instead, use the [CSV](csv) route. See [Troubleshooting](troubleshooting#redcap-export-mode).

</details>
<details>
<summary>Can I use the mapping file to customize synthesized `datasets` and `cohorts` for any `*2bff` conversion?</summary>


No. Mapping-based augmentation of synthesized `datasets` and `cohorts` is currently available only for the routes that use a mapping file: `csv2bff`, `redcap2bff`, and `cdisc2bff`.

For those conversions, the top-level `beacon` section of the mapping file can override metadata such as `id`, `name`, `description`, `version`, `externalUrl`, `cohortType`, or `cohortDataTypes`.

This does not currently apply to `omop2bff` or `pxf2bff`.

</details>
<details>
<summary>Which formats accept gzipped (`.gz`) files?</summary>


Based on the current I/O code, gzip support is available for these file families:

| File family | Typical use | Read `.gz` | Write `.gz` | Notes |
| --- | --- | --- | --- | --- |
| JSON / YAML structured files | `BFF`, `PXF`, `JSON-LD`, flattened `JSON/YAML`, mapping files, schema files | Yes | Yes | Implemented through the shared JSON/YAML I/O layer for `.json`, `.yaml`, `.yml`, `.jsonld`, `.yamlld`, `.ymlld` and their `.gz` variants |
| CSV / TSV / TXT tabular inputs | `csv2*`, `redcap2*`, REDCap dictionary files | Yes | N/A | Input readers accept `.csv.gz`, `.tsv.gz` and `.txt.gz` |
| SQL dumps | `omop2*` from `.sql` dumps | Yes | N/A | OMOP SQL input accepts `.sql.gz` |
| Streamed OMOP output | `omop2bff --stream` | N/A | Yes | CLI restricts streamed OMOP output to `json` or `json.gz` |
| OMOP table output | `*2omop` | N/A | Yes | Use `-oomop --out-dir DIR` to get `TABLE.csv` files. Use `--out-name TABLE=filename.csv.gz` to rename or gzip specific tables |
| CSV / TSV output | `bff2csv`, `pxf2csv`, search-audit TSV | N/A | Yes | The current writers accept `.csv.gz` and `.tsv.gz` in addition to plain text output |

In practice, gzip is supported both for structured JSON/YAML-style outputs and for the main CSV/TSV output paths.


</details>
## Installation

<details>
<summary>I am installing `Convert-Pheno` from source ([non-containerized version](download-and-installation#non-containerized)) but I can't make it work. Any suggestions?</summary>


See [Troubleshooting](troubleshooting#python-api--local-bridge-installation).
</details>
