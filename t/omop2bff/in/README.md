# OMOP test fixtures

These fixtures are derived from the OHDSI `Eunomia` example dataset:

- <https://github.com/OHDSI/Eunomia>

This directory intentionally contains two different kinds of OMOP input
fixtures used by the test suite.

## 1. Full SQL fixture

- `omop_cdm_eunomia.sql`

This is the larger PostgreSQL dump fixture used for:

- `omop2bff`
- `omop2pxf`
- streamed SQL-based OMOP regressions

## 2. Reduced plain CSV fixtures

- `PERSON.csv`
- `CONCEPT.csv`
- `DRUG_EXPOSURE.csv`

These are lightweight plain-CSV fixtures used to exercise the OMOP CLI/API
paths without relying on a full OMOP export.

Important notes:

- `CONCEPT.csv` is intentionally reduced and is **not** a complete OMOP
  vocabulary table.
- These files are useful for regression-testing mechanics of the conversion
  path, but they are **not** a gold-standard fixture for complete OHDSI concept
  resolution.
- In this reduced path, some concept-dependent values may degrade to defaults
  such as `NCIT:C126101 / Not Available` instead of representing full semantic
  OMOP-to-Beacon mapping.

These reduced CSV fixtures are currently covered by the CLI regression test:

- `t/19-cli-regression.t`

with a non-stream command equivalent to:

```bash
../../../bin/convert-pheno -iomop PERSON.csv CONCEPT.csv DRUG_EXPOSURE.csv \
  -obff individuals_csv.json --test
```

## 3. Gzipped CSV fixtures

- `gz/PERSON.csv.gz`
- `gz/CONCEPT.csv.gz`
- `gz/DRUG_EXPOSURE.csv.gz`

These are the fixtures used for streamed OMOP CSV regressions.

They are covered by:

- `t/04-api-stream-omop.t`
- `t/20-cli-stream-omop.t`

with a command equivalent to:

```bash
../../../bin/convert-pheno -iomop gz/PERSON.csv.gz gz/CONCEPT.csv.gz gz/DRUG_EXPOSURE.csv.gz \
  -obff individuals_csv.json.gz --stream --ohdsi-db --sep $'\t' --max-lines-sql 2700 --test
```
