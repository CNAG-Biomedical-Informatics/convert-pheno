??? Hint "About text similarity in database searches"
    `Convert-Pheno` comes with a few pre-configured databases and it will search for ontologies/terminologies there. Three types of searches can be performed:

     1. `exact` (default)

         Retrieves only **exact matches** for a specified 'label'.

     2. `mixed` (needs `--search mixed`)

         **Hybrid search:** The script will begin by attempting an exact match for 'label', and if it is unsuccessful, it will then conduct a search based on string similarity (token-based) and select the ontology term with the highest score. 

     3. `fuzzy` (needs `--search fuzzy`)

        **Hybrid search:** The script will begin by attempting an exact match for 'label', and if it is unsuccessful, it will then conduct a search based on string similarity (token-based) that accounts per 90% of teh score, and a fuzzy search that accounts for 10%. Then the ontology term with the highest score is selected     


     Example (NCIt ontology): 

     Search phrase: **Exercise pain management** with `exact` search.

     - exact match: Exercise Pain Management

     Search phrase: **Brain Hemorrhage** with `mixed` search.

     - exact match: NA

     - similarity match: Intraventricular Brain Hemorrhage

     `--min-text-similarity-score` sets the minimum value for the Cosine / Sorensen-Dice coefficient. The default value (0.8) is very conservative.

     Note that `mixed|fuzzy` search requires more computational time and its results can be unpredictable. Please use it with caution.

     **Example:** 
 
     Find below an example of the resulfs for the query `Sudden Death Syndrome` on the local [NCIt](https://ncithesaurus.nci.nih.gov/ncitbrowser) database.


     | Query                 | Search method  |NCIt match (label) | NCIt code (id) | Cosine | Dice | Levenshtein |
     |                       |                |        |      |     |     |   |
     | Sudden Death Syndrome | `exact` |           `NA`                                    |    `NA`      | `NA` | `NA`| `NA`|
     |                       | `mixed` | CDISC SDTM Sudden Death Syndrome Type Terminology | NCIT:C101852 | 0.65 | 0.6 | `NA`|
     |                       |         | Family History of Sudden Arrythmia Death Syndrome | NCIT:C168019 | 0.65 | 0.6 | `NA`|
     |                       |         | Family History of Sudden Infant Death Syndrome    | NCIT:C168209 | 0.65 | 0.6 | `NA`|
     |                       |         | Sudden Infant Death Syndrome                      | NCIT:C85173  | 0.86 | 0.86| `NA`|
     |                       | `fuzzy` | CDISC SDTM Sudden Death Syndrome Type Terminology | NCIT:C101852 | 0.65 | 0.6 |  0  |
     |                       |         | Family History of Sudden Arrythmia Death Syndrome | NCIT:C168019 | 0.65 | 0.6 |  0  |
     |                       |         | Family History of Sudden Infant Death Syndrome    | NCIT:C168209 | 0.65 | 0.6 |  0  |
     |                       |         | Sudden Infant Death Syndrome                      | NCIT:C85173  | 0.86 | 0.86|  0  |

     Here, utilizing the default `--search` method (`exact`) will yield no matches. However, by employing `--search mixed`, we would identify `Sudden Infant Death Syndrome` as it registers the highest `cosine` score. If we had configured the `--min-text-similarity-score` to 0.9, we would not have found any matches.
