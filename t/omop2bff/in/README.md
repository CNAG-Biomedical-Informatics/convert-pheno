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

Note:

- `concept_id = 5001` was added to the fixture `CONCEPT` data so this SQL
  export remains self-contained without `--ohdsi-db`.

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

## 3. Reduced MIMIC specimen fixture

- `mimic_specimen/PERSON.csv`
- `mimic_specimen/CONCEPT.csv`
- `mimic_specimen/SPECIMEN.csv`

These files are a reduced fixture derived from the public MIMIC-IV demo OMOP
CSV export hosted by PhysioNet:

- <https://physionet.org/content/mimic-iv-demo-omop/0.9/>

Source files used:

- `1_omop_data_csv/person.csv`
- `1_omop_data_csv/specimen.csv`

Important notes:

- This fixture is intentionally reduced to only the rows needed for OMOP
  `SPECIMEN` -> Beacon `biosamples` regression tests.
- `PERSON.csv` keeps the original MIMIC `person_id` values for the selected
  rows.
- The demo OMOP `person.csv` provides year-level birth data; this fixture
  synthesizes `birth_datetime`, `month_of_birth`, and `day_of_birth` as
  January 1 of `year_of_birth` so `collectionMoment` tests remain
  deterministic.
- `CONCEPT.csv` is reduced to the concept ids referenced by the selected
  `PERSON` and `SPECIMEN` rows.

These reduced MIMIC specimen CSV fixtures are covered by:

- `t/26-omop-biosamples.t`

Provenance details for `mimic_specimen/`:

- Download source: PhysioNet MIMIC-IV demo OMOP dataset, version `0.9`
- Source URLs:
  - <https://physionet.org/files/mimic-iv-demo-omop/0.9/1_omop_data_csv/person.csv>
  - <https://physionet.org/files/mimic-iv-demo-omop/0.9/1_omop_data_csv/specimen.csv>
- Retrieved for this fixture on `2026-04-15`
- Selected original MIMIC `person_id` values kept in the fixture:
  - `4668337230155062633`
  - `2288881942133868955`
  - `3192038106523208432`
  - `7131048714591189903`
- `SPECIMEN.csv` rows are reduced from those public MIMIC rows for biosample
  regression coverage only
- `CONCEPT.csv` is not copied from the MIMIC download; it is a reduced local
  companion fixture containing only the OMOP concept rows needed by the
  selected `PERSON` and `SPECIMEN` rows

## 4. Gzipped CSV fixtures

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
