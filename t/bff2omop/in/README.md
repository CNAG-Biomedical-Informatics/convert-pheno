# BFF-to-OMOP Examples

The desktop uses `t/bff2pxf/in/individuals.json` for all BFF input routes.
To convert that same fixture and inspect its terminology audit:

```bash
mkdir -p omop-output
bin/convert-pheno \
  -ibff t/bff2pxf/in/individuals.json \
  -oomop --out-dir omop-output \
  --ohdsi-db \
  --term-audit omop-audit.xlsx
```

Not every term in this fixture resolves to an OMOP standard concept in the
required domain. Review the audit rather than treating all concept-zero values
as equivalent: some preserve source text, while others need terminology review.

## Optional Terminology Mapping

`local-terms.json` is a separate, small regression fixture using two invented
local terms. It is not the desktop default. `terminology.yaml` supplies their
reviewed correspondences:

```bash
mkdir -p omop-mapped-output
bin/convert-pheno \
  -ibff t/bff2omop/in/local-terms.json \
  -oomop --out-dir omop-mapped-output \
  --ohdsi-db \
  --mapping-file t/bff2omop/in/terminology.yaml \
  --term-audit omop-mapped-audit.xlsx
```

Use `--path-to-ohdsi-db DIRECTORY` if the database is installed elsewhere.

Each terminology key names a BFF field, ignoring array indices. `from: id`
matches the original term ID; `from: value` matches its label. Alias keys are
case-sensitive after surrounding whitespace is removed. Unlisted values retain
the normal lookup behavior.

The alias becomes the database query. `column: id` looks up a vocabulary CURIE
such as `SNOMED:195662009` or an OMOP identifier such as `OHDSI:4112343`.
Without `column`, the query searches labels using the selected search mode.
The canonical target label always comes from the database. Domain, standard
concept, relationship, and ambiguity checks still apply; an invalid configured
ID cannot fall back to a label search.

Original labels and source concept identifiers remain in OMOP source columns.
The audit records the original term, the query, the result, and a `mapped_`
decision reason when an alias was applied. These rules apply only to BFF-to-OMOP,
not BFF-to-Phenopackets or source-to-BFF mappings.

## Provenance

The local-term example and mapping were authored for Convert-Pheno testing and
contain no real participant data. Standard terminology identifiers are covered
by the repository's OHDSI test vocabulary. The existing `individuals.json`
fixture is unchanged.
