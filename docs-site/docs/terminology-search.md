---
title: Terminology Search
sidebar_label: Terminology Search
---

Convert-Pheno searches a bundled terminology database only when a mapping rule
requests it. The search compares text; it does not determine whether two
clinical concepts are semantically equivalent.

For most conversions, start with `exact`, write a terminology audit, and add
reviewed aliases for source values that do not resolve.

## Recommended Workflow

1. Run the conversion with `--term-audit terminology.tsv`.
2. Review rows whose `match_status` is `not_found`.
3. If the intended database label is known, add it as an alias in the mapping
   file and run again.
4. Use `mixed` or `fuzzy` only when reviewed aliases are not practical.
5. Treat every similarity match as a proposed lexical match that still needs
   domain review.

## What Is Searched

Mapping rules can resolve terminology in three ways:

- A configured `term` or `terms` entry is used directly and does not search a
  database.
- An `id` or OMOP `concept_id` is always looked up exactly. The database
  supplies the canonical label.
- A label `query` uses the selected `--search` mode.

An alias translates a source value into the reviewed database label to query:

```yaml
terminology:
  AE.AESEV:
    query:
      from: value
      aliases:
        MILD_GRADE: Mild
```

Here, `MILD_GRADE` is a local source value and `Mild` is the reviewed label
searched in the terminology database. The `aliases` object is selective, not
an exhaustive list of allowed values: an unlisted value such as `SEVERE` is
queried using its original source label. Searches are case-insensitive, so an
alias that changes only capitalization would be unnecessary. Add an alias only
when the source text and intended database label genuinely differ. See
[Mapping Files](mapping-files) for direct terms and complete rule syntax.

## Choose a Search Mode

<div className="termReferenceTable termReferenceTable--modes">

| Mode | What it does | When to use it |
| --- | --- | --- |
| `exact` | Case-insensitive label equality | Default; preferred with reviewed aliases |
| `mixed` | Exact lookup, then order-independent token ranking | Labels differ by word order or contain additional words |
| `fuzzy` | Exact and strict search, then a bounded relaxed search with composite ranking | A multi-word label may contain one misspelled or missing token |

</div>

<details>
<summary>How mixed and fuzzy search retrieve and score candidates</summary>

For `mixed` and `fuzzy`, candidate retrieval and candidate scoring are separate
steps. The query is split into distinct literal Unicode words, and strict
retrieval requires every word in any order. Here, **literal** means that words
such as `OR` and `NOT` and symbols such as quotes or parentheses cannot become
SQLite search syntax; it does not mean that the complete label is searched as
an ordered phrase. Only `fuzzy` may retry while allowing one word to be absent.

`mixed` ranks the retrieved labels with an order-independent cosine or Dice
token score. Consequently, the query `Foo Bar Baz Bax` and candidate
`Bax Baz Bar Foo` have a `mixed` score of `1.0000`: they have complete token
overlap, but they are **not** an exact label match. With the default fuzzy
weights, the same pair scores approximately `0.9467` because `fuzzy` combines
the token score with an order-sensitive, character-level Levenshtein score.
The original query is retained for scoring and audit provenance.

:::note[What full-text search means here]
The bundled search tables use [SQLite FTS5](https://www.sqlite.org/fts5.html)
with its default `unicode61` tokenizer. It treats runs of Unicode letters and
numbers as words, ignores case, uses spaces and punctuation as separators, and
normally removes Latin diacritics. It does not perform stemming or understand
clinical meaning. Convert-Pheno quotes each distinct query word and joins the
words with `AND`, so FTS retrieves labels containing all of them in any order;
`mixed` or `fuzzy` then scores those candidates separately.
:::

</details>

```bash
convert-pheno \
  -icsv clinical.csv \
  --mapping-file mapping.yaml \
  --search mixed \
  --term-audit terminology.tsv \
  -obff individuals.json
```

`mixed` and `fuzzy` accept `--text-similarity-method cosine|dice` and
`--min-text-similarity-score` (default `0.8`). `fuzzy` also accepts
`--levenshtein-weight` (default `0.1`). Lowering the threshold may find more
labels, but it also increases the risk of an incorrect mapping.

:::warning[Scores measure text, not clinical meaning]
`best_candidate_score` is a lexical match score, not a probability or semantic
confidence value. `1.0` means exact label equality only when
`lookup_resolution` is `exact`. Under `mixed`, `1.0` can instead mean complete
token overlap with a different word order. Similarity results remain reviewable
even when their score is maximal.
:::

## Choose an Audit Format

`--term-audit` selects the report format from its filename:

<div className="termReferenceTable">

| Extension | Best suited to |
| --- | --- |
| `.tsv` | Lightweight inspection and scripted processing |
| `.tsv.gz` | The same tabular report with lower storage use |
| `.xlsx` | Manual review with a run summary, filters, frozen headings, and colored rows |

</div>

```bash
convert-pheno ... --term-audit terminology.xlsx
```

The XLSX workbook contains **Summary** and **Terminology Audit** sheets. Green
rows are exact or configured results, amber rows use similarity and merit
review, red rows are unresolved, and gray rows were not searched or retain a
source fallback. These colors organize review; they are not measures of
clinical confidence.

To keep the initial view manageable, the audit sheet shows 14 review-focused
columns. Repeated run settings and low-level resolution fields remain in the
workbook but are hidden by default; use the spreadsheet's **Unhide columns**
command when that evidence is needed. TSV output retains every column.

Excel worksheets hold at most 1,048,575 audit decisions plus the header. Use
`.tsv.gz` for larger conversions.

## Review the Audit

Start with `review_action`, which gives the suggested next step for each
decision. Use the candidate score and score gap when a row needs closer review.

<details>
<summary>Complete audit columns and resolution details</summary>

The audit keeps one row per terminology decision. Its columns are grouped by
purpose:

<div className="termReferenceTable termReferenceTable--groups">

| Purpose | Main columns |
| --- | --- |
| Source | `row`, `source_record`, `source_field`, `source_value`, `source_label` |
| Lookup | `lookup_query`, `lookup_column`, `ontology` |
| Emitted term | `converted_term_label`, `converted_term_id` |
| Decision | `match_status`, `decision_reason`, `review_action`, `match_source`, `lookup_resolution`, `fallback_action` |
| Run settings | `configured_search_mode`, `effective_search_mode`, `text_similarity_method`, `min_text_similarity_score`, `levenshtein_weight` |
| Candidate review | `retrieval_path`, `best_candidate_label`, `best_candidate_id`, `best_candidate_score`, `score_margin` |

</div>

The search mode records the policy selected for the run. `retrieval_path`
instead reports how candidates were obtained for this particular lookup:

- `exact_lookup`: indexed equality on the requested database column
- `all_tokens`: every distinct literal query word was required, in any order
- `one_token_relaxed`: fuzzy search permitted one missing token
- `not_used`: the mapping supplied the term directly

`lookup_query` keeps the original text supplied to the search. The quoted
SQLite expression generated internally for literal retrieval is deliberately
not written to the audit.

The score means:

- `exact`: `1.0` represents case-insensitive label equality
- `mixed`: the selected order-independent cosine or Dice token score
- `fuzzy`: the weighted token and character-level Levenshtein score

The audit also records the best candidate when it falls below the threshold and
is therefore **not** emitted. `score_margin` is the difference between the best
and second-best candidate scores; a small value indicates a more ambiguous
result. Empty candidate fields mean that no database candidate was evaluated.

`decision_reason` states why the term was emitted or withheld. Its principal
values are `exact_match`, `similarity_accepted`, `score_below_threshold`,
`spelling_variant_accepted`, `no_candidate`, `direct_mapping`, and
`not_searched`.

</details>

`review_action` turns that evidence into one suggested next step:

<div className="termReferenceTable termReferenceTable--actions">

| Value | Suggested action |
| --- | --- |
| `keep` | Keep an exact, direct, or configured result |
| `review_similarity` | Confirm that the lexical match is clinically correct |
| `resolve_or_accept_fallback` | Map the value explicitly or knowingly retain its fallback |
| `review_source_fallback` | Inspect a source-derived term that was not searched |

</div>

A practical review order is:

1. `review_action=resolve_or_accept_fallback`
2. `review_action=review_similarity`
3. `review_action=review_source_fallback`
4. low `best_candidate_score` or a small `score_margin`

### Example audit review

This compact view illustrates how the audit can be reviewed in a spreadsheet.
The colors indicate the **review action**, not clinical confidence.

<div className="termAuditSheet">

| Row | Source value | Retrieval path | Best candidate | Score | Score gap | Outcome | Decision reason | Review action |
| ---: | --- | --- | --- | ---: | ---: | --- | --- | --- |
| 1 | `Acute Bacterial Prostatitis` | `exact_lookup` | Acute Bacterial Prostatitis<br />`NCIT:C92957` | 1.0000 | - | <span className="termAuditStatus termAuditStatus--accepted">Matched</span> | Exact database match | Keep |
| 2 | `Sudden Death Syndrome` | `all_tokens` | Sudden Infant Death Syndrome<br />`NCIT:C85173` | 0.8544 | 0.2196 | <span className="termAuditStatus termAuditStatus--review">Review</span> | Score met the `0.8000` threshold | Confirm the clinical meaning |
| 3 | `Sudden Infant Deth Syndrome` | `one_token_relaxed` | Sudden Infant Death Syndrome<br />`NCIT:C85173` | 0.9514 | 0.3825 | <span className="termAuditStatus termAuditStatus--review">Review</span> | Single-token spelling variant accepted | Confirm the spelling correction |
| 4 | `Sudden Adult Death Syndrome` | `one_token_relaxed` | Sudden Infant Death Syndrome<br />`NCIT:C85173` | 0.7571 | 0.1969 | <span className="termAuditStatus termAuditStatus--rejected">Rejected</span> | `0.7571` is below the `0.8000` threshold | Map only if clinically justified |
| 5 | `Unmapped local term` | `exact_lookup` | - | - | - | <span className="termAuditStatus termAuditStatus--empty">No candidate</span> | No database candidate | Map explicitly or retain the fallback |

</div>

Green marks a direct match, amber marks a result that merits semantic review,
red marks a candidate rejected by the configured threshold, and gray marks a
lookup with no candidate.

:::note[How to read the score gap]
The **score gap** is the best candidate's score minus the second-best score. In
row 2, `0.8544 - 0.6348 = 0.2196`. A small gap indicates competing candidates
with similar lexical scores; a larger gap indicates clearer separation. `-`
means that no second candidate was scored. The gap does not measure clinical
confidence.
:::

## Correct a Result

When the source value and intended concept are known, prefer a mapping-file
change over repeatedly lowering the global threshold:

- Add an alias when the database already contains the intended label.
- Add a direct `term` or `terms` entry when the identifier and label have been
  curated.
- Keep the fallback when no justified terminology mapping exists.

This makes the decision reproducible and prevents one permissive search setting
from affecting unrelated fields.

<details>
<summary>Scoring formulas and worked NCIT example</summary>

`mixed` and `fuzzy` first use SQLite full-text search to retrieve candidates.
If strict retrieval is empty, `fuzzy` can permit one missing token for queries
containing 2-12 unique tokens. SQLite BM25 ordering limits this relaxed pass to
200 candidates. Queries containing only one token are not broadened.

For relaxed fuzzy candidates with the same number of tokens, Convert-Pheno can
recognize exactly one unmatched token pair as a spelling variant when its
normalized token-level Levenshtein similarity is at least `0.8`. That partial
token match is included in the selected cosine or Dice score. Multiple
differing tokens and less similar substitutions retain the ordinary token
score.

Normalized Levenshtein similarity is:

$$
\operatorname{NormalizedLevenshtein}(s_1,s_2)
= 1 - \frac{\operatorname{lev}(s_1,s_2)}{\max(|s_1|,|s_2|)}
$$

The fuzzy score is:

$$
C(s_1,s_2)
= (1-\beta)\operatorname{TokenSimilarity}(s_1,s_2)
+ \beta\operatorname{NormalizedLevenshtein}(s_1,s_2)
$$

Here, $\beta$ is `--levenshtein-weight`. Its default is `0.1`.

For the query `Sudden Death Syndrome`, strict NCIT search returns these
candidates. Scores are rounded to two decimal places.

<div className="termReferenceTable termReferenceTable--scores">

| Candidate | NCIT code | Cosine | Dice | Levenshtein | Fuzzy score |
| --- | --- | ---: | ---: | ---: | ---: |
| CDISC SDTM Sudden Death Syndrome Type Terminology | `NCIT:C101852` | 0.65 | 0.60 | 0.43 | 0.63 |
| Family History of Sudden Arrythmia Death Syndrome | `NCIT:C168019` | 0.65 | 0.60 | 0.43 | 0.63 |
| Family History of Sudden Infant Death Syndrome | `NCIT:C168209` | 0.65 | 0.60 | 0.46 | 0.63 |
| Sudden Infant Death Syndrome | `NCIT:C85173` | 0.87 | 0.86 | 0.75 | 0.85 |

</div>

With the default threshold of `0.8`, `mixed` and `fuzzy` select
`NCIT:C85173`; `exact` returns no match.

For `Sudden Infant Deth Syndrome`, relaxed fuzzy search retrieves
`NCIT:C85173`. `Deth` and `Death` have token-level similarity `0.8`; including
that partial token overlap raises the fuzzy score from `0.7714` to `0.9514`.
The unchanged default threshold accepts the candidate and records
`decision_reason=spelling_variant_accepted` in the audit.

By contrast, `Sudden Adult Death Syndrome` retrieves the same best candidate
but scores `0.7571`. `Adult` and `Infant` are not treated as a spelling pair,
so the candidate remains below the default threshold and is not emitted.

</details>

## Performance

Exact lookups use regular SQLite indexes. Similarity search evaluates FTS
candidates and is slower. The relaxed fuzzy pass runs only when strict search
returns no candidates. TSV audits add sequential writes; XLSX adds workbook
packaging and formatting but still writes decisions incrementally.
