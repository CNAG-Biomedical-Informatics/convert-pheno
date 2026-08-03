# Dataset-JSON reference outputs

These files demonstrate two distinct terminology contracts using the same
synthetic SDTM study:

- `individuals.json` is the baseline structural conversion without an optional
  terminology mapping. Source-derived `CDISC:` identifiers are expected.
- `terminology/individuals.json` adds `in/sdtm_terminology.yaml`. Reviewed
  direct terms and label queries resolve selected fields to NCIT; fields not
  covered by that mapping retain their source-derived identifiers.

Keeping the canonical `individuals.json` filename means both references can be
passed directly to the BFF validator from their respective directories. The
enriched reference is not intended to be a complete SDTM-to-ontology
crosswalk. It demonstrates that terminology resolution is explicit,
data-owner-controlled, and independently auditable.

Run the enriched example from the repository root:

```bash
bin/convert-pheno \
  -idataset-json t/datasetjson2bff/in/*.json \
  --mapping-file t/datasetjson2bff/in/sdtm_terminology.yaml \
  --term-audit terminology.xlsx \
  -obff individuals.json \
  --test -O
```
