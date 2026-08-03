# Dataset-XML reference outputs

These references make the transport and terminology scenarios explicit:

- `individuals.json` uses the main Dataset-XML and Define-XML fixtures. It
  emphasizes metadata resolution and structural SDTM conversion; source-derived
  `CDISC:` identifiers are expected when no authoritative term is supplied.
- `terminology/individuals.json` uses `in/terminology/`. Its first ethnicity is
  resolved from Define-XML `nci:ExtCodeID` metadata to `NCIT:C41222`; its second
  ethnicity intentionally remains `CDISC:ETHNIC.UNKNOWN`.

The second file therefore demonstrates both successful identifier lookup and
the safe fallback within one small reference output. Keeping the canonical
`individuals.json` filename means both references can be passed directly to the
BFF validator from their respective directories.

Run it from the repository root:

```bash
bin/convert-pheno \
  -idataset-xml t/datasetxml2bff/in/terminology/dm.xml \
  --define-xml t/datasetxml2bff/in/terminology/define.xml \
  --term-audit terminology.xlsx \
  -obff individuals.json \
  --test -O
```
