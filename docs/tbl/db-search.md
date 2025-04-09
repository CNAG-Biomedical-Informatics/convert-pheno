??? Hint "About text similarity in database searches"

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
    

??? Example "Composite Similarity Score"
    
    The composite similarity score is computed as a weighted sum of two measures: the token-based similarity and the normalized Levenshtein similarity.
    
    #### 1. Token-Based Similarity
    
    This is calculated using methods like cosine or Dice similarity to measure how similar the tokens (words) of two strings are.
    
    #### 2. Normalized Levenshtein Similarity
    
    The normalized Levenshtein similarity is defined as:
    
    $$
    \text{NormalizedLevenshtein}(s_1, s_2) = 1 - \frac{\text{lev}(s_1, s_2)}{\max(|s_1|, |s_2|)}
    $$
    
    Where:
    - \(\text{lev}(s_1, s_2)\) is the Levenshtein edit distance—the minimum number of insertions, deletions, or substitutions required to change \(s_1\) into \(s_2\).
    - \(|s_1|\) and \(|s_2|\) are the lengths of the strings \(s_1\) and \(s_2\), respectively.
    
    This formula produces a score between 0 and 1, with **1.0** meaning identical strings and **0.0** meaning completely different strings.
    
    #### 3. Composite Score Formula
    
    The final composite similarity score \(C\) is a weighted combination of the two metrics:
    
    $$
    C(s_1, s_2) = \alpha \cdot \text{TokenSimilarity}(s_1, s_2) + \beta \cdot \text{NormalizedLevenshtein}(s_1, s_2)
    $$
    
    Where:
    - \(\alpha\) (or `token_weight`) is the weight assigned to the token-based similarity.
    - \(\beta\) (or `lev_weight`) is the weight assigned to the normalized Levenshtein similarity.
    
    A common default is to set \(\alpha = 0.9\) and \(\beta = 0.1\), emphasizing the token-based similarity. However, for short strings (4–5 words), you might consider adjusting the balance (for example, \(\alpha = 0.95\) and \(\beta = 0.05\)) if small typographical differences are less critical.
