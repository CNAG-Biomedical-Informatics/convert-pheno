## Provenance

These Dataset-JSON v1.1 documents are project-authored synthetic fixtures.
They were created for Convert-Pheno regression tests and were not copied from
an external study or repository.

The fixtures follow the CDISC Dataset-JSON exchange structure documented at:

- <https://www.cdisc.org/standards/data-exchange/dataset-json>

Each JSON document represents one SDTM domain in the synthetic
`STUDY-JSON-01` study. Together they cover the first-class `DM`, `MH`, `AE`,
`LB`, `VS`, `CM`, `EX`, and `PR` mappings, study-level `TS` metadata, and an
intentionally unmapped `QS` domain used to test source provenance.

All participant identifiers and clinical values are fictional and exist only
for testing.

## Terminology scenarios

The baseline reference output intentionally runs without an optional mapping
file. Term-bearing values without authoritative identifiers therefore use
source-derived `CDISC:` CURIEs; this tests preservation rather than failed
search.

`sdtm_terminology.yaml` exercises the separate reviewed-enrichment path. It
contains curated direct severity terms, one code-to-label alias, ordinary exact
label queries, and a curated disease term. The paired references are described
under [`../out/README.md`](../out/README.md). Fields not covered by that compact
mapping continue to use source-derived identifiers by design.
