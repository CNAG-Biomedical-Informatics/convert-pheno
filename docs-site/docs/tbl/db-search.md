---
title: Terminology Search
sidebar_label: Terminology Search
---

Convert-Pheno can resolve source values against the bundled terminology
databases when a conversion rule requests it. Search is **mapping-controlled**:
the software does not decide that two clinical terms are equivalent unless the
source metadata or mapping file supplies the basis for that decision.

## Resolution Order

For SDTM Dataset-JSON and Dataset-XML fields, Convert-Pheno uses this order:

1. A curated `term` or matching entry in `terms` from the mapping file
2. An NCI identifier explicitly supplied by Define-XML
3. A configured label query, including a reviewed alias
4. The source-derived `CDISC:` term when none of the above resolves

Direct mapping terms bypass SQLite. A Define-XML NCI identifier is searched in
the `id` column to obtain its canonical NCIT label. Only configured label
queries use the selected `--search` mode.

Other mapping-file routes use the same direct-term and label-query behavior,
without the Define-XML step. FHIR and already coded source formats preserve
recognized source codings according to their format-specific mapping instead
of applying this search contract automatically.

## Mapping A Label Query

An alias records a reviewed relationship between a source value and the label
expected in the selected terminology database:

```yaml
terminology:
  AE.AESEV:
    query:
      from: value
      aliases:
        MILD: Mild
```

Here, `MILD` is the value in the SDTM dataset and `Mild` is the database label
to search. The alias is not an ontology identifier and does not bypass lookup.

When the identifier and display are already curated, use `terms` instead:

```yaml
terminology:
  AE.AESEV:
    terms:
      MILD:
        id: NCIT:C70666
        label: Mild
```

`term` applies one fixed term to the field. `terms` selects direct terms by
source value. A rule may combine `terms` with `query`: matching values use the
curated term, while the remaining values use the query.

## Identifier Lookup

Identifier lookup and label search are deliberately different:

- `id` and OMOP `concept_id` lookups are always exact
- the global `--search` setting does not make identifier lookup fuzzy
- the identifier returned by the database is paired with its canonical label
- the audit retains the original source value and display separately

For example, a Define-XML `Alias` with `Context="nci:ExtCodeID"` and
`Name="C41222"` resolves to `NCIT:C41222` and the current NCIT display. Other
Define-XML alias contexts are not treated as NCI identifiers.

## Label Search Modes

| Mode | Behavior | Suggested use |
| --- | --- | --- |
| `exact` | Case-insensitive exact label match | Default and preferred when aliases are reviewed |
| `mixed` | Exact match, then token-similarity fallback | Controlled review when exact labels are unavailable |
| `fuzzy` | Exact match, then token and normalized Levenshtein ranking | Misspellings or minor textual variation requiring closer review |

Configure the mode for the run:

```bash
convert-pheno \
  -icsv clinical.csv \
  --mapping-file mapping.yaml \
  --search mixed \
  --min-text-similarity-score 0.8 \
  --term-audit-tsv terminology.tsv \
  -obff individuals.json
```

`mixed` and `fuzzy` use `--text-similarity-method cosine|dice` and
`--min-text-similarity-score` (default `0.8`). `fuzzy` also uses
`--levenshtein-weight` (default `0.1`). Lower thresholds increase recall but
also increase the risk of semantically incorrect matches.

:::warning[Review similarity matches]
Similarity is lexical, not clinical. A high text score does not establish that
two concepts are semantically equivalent. Prefer reviewed aliases or direct
terms when the data owner knows the intended concept.
:::

## Terminology Audit

Add `--term-audit-tsv FILE` to write one row for each terminology decision.
The report also supports `.tsv.gz` output.

The most useful columns are:

| Column | Meaning |
| --- | --- |
| `source_record`, `source_field` | Location of the source value |
| `source_value` | Raw or normalized value supplied by the source |
| `source_label` | Source display, including a Define-XML decode when present |
| `lookup_query`, `lookup_column` | Value and database column actually searched |
| `converted_term_label`, `converted_term_id` | Term emitted by the conversion |
| `configured_search_mode` | Global label-search mode for the run |
| `effective_search_mode` | Actual mode; identifier lookup remains `exact` and direct terms are `not_used` |
| `match_status`, `match_source` | Whether and where resolution occurred |
| `lookup_resolution` | Exact, similarity, direct mapping, or source fallback |
| `fallback_action` | Whether a default or source-derived term was retained |

This distinction makes cases such as the following reviewable:

- source value `MILD`, alias query `Mild`, result `NCIT:C70666`
- source display `Not Hispanic or Latino`, Define-XML ID `C41222`, canonical NCIT result
- source value `UNKNOWN`, no supported identifier or query, retained `CDISC:ETHNIC.UNKNOWN`

The audit replaces the former `--search-audit-tsv` option. It covers direct
terms, identifier resolution, label searches, and fallbacks rather than only
SQLite search results.

## Performance

Exact label and identifier lookups use indexed SQLite columns. `mixed` and
`fuzzy` search are slower because they evaluate full-text candidates and
similarity scores. The audit itself adds only sequential TSV writes and is
normally small compared with similarity search or conversion work.
