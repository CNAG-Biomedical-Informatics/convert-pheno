# Regression Fixtures and Runnable Examples

The directories under `t/` serve two purposes: they are the inputs and expected
outputs used by the automated tests, and they are small examples that can be run
from a source checkout. The test suite compares generated data structurally, so
formatting differences alone do not require reference-file changes.

Fixtures are regression contracts, not curated semantic showcase datasets.
Baseline outputs intentionally exercise safe source-derived fallbacks when the
input supplies no authoritative identifier and no optional terminology mapping
is requested. CDISC fixtures provide separate terminology-enriched references
so both behaviors remain visible and tested.

## Start with Three Core Routes

Run these commands from the repository root. `--test` removes changing runtime
metadata and `-O` permits replacing an earlier local result.

PXF to BFF:

```bash
bin/convert-pheno \
  -ipxf t/pxf2bff/in/pxf.json \
  -obff individuals.json \
  --test -O
```

Reference output: [`t/pxf2bff/out/individuals.json`](pxf2bff/out/individuals.json)

BFF to PXF:

```bash
bin/convert-pheno \
  -ibff t/bff2pxf/in/individuals.json \
  -opxf pxf.json \
  --test -O
```

Reference output: [`t/bff2pxf/out/pxf.json`](bff2pxf/out/pxf.json)

OMOP CSV tables to BFF:

```bash
bin/convert-pheno \
  -iomop \
  t/omop2bff/in/PERSON.csv \
  t/omop2bff/in/CONCEPT.csv \
  t/omop2bff/in/DRUG_EXPOSURE.csv \
  -obff individuals-omop.json \
  --test -O
```

Reference output: [`t/omop2bff/out/individuals_csv.json`](omop2bff/out/individuals_csv.json)

## Fixture Index

| Input format | Input directory | Reference output directories |
| --- | --- | --- |
| BFF | [`bff2pxf/in`](bff2pxf/in) | `bff2pxf/out`, `bff2omop/out`, `bff2csv/out`, `bff2jsonf/out` |
| cBioPortal clinical study | [`cbioportal2bff/in`](cbioportal2bff/in) | Semantic assertions in [`37-cbioportal.t`](37-cbioportal.t) |
| PXF | [`pxf2bff/in`](pxf2bff/in) | `pxf2bff/out`, `pxf2csv/out`, `pxf2jsonf/out` |
| OMOP-CDM | [`omop2bff/in`](omop2bff/in) | `omop2bff/out`, `omop2pxf/out` |
| CSV | [`csv2bff/in`](csv2bff/in) | `csv2bff/out`, `csv2pxf/out`, `csv2omop/out` |
| REDCap | [`redcap2bff/in`](redcap2bff/in) | `redcap2bff/out`, `redcap2pxf/out` |
| CDISC-ODM | [`cdiscodm2bff/in`](cdiscodm2bff/in) | `cdiscodm2bff/out`, `cdiscodm2pxf/out` |
| CDISC Dataset-JSON | [`datasetjson2bff/in`](datasetjson2bff/in) | `datasetjson2bff/out`, `datasetjson2pxf/out`, `datasetjson2omop/out` |
| CDISC Dataset-XML | [`datasetxml2bff/in`](datasetxml2bff/in) | `datasetxml2bff/out`; PXF and OMOP behavior in `38-datasetxml.t` |
| FHIR R4 Bundle | [`fhir2bff/in`](fhir2bff/in) | `fhir2bff/out`, `fhir2pxf/out`, `fhir2omop/out` |
| openEHR canonical JSON | [`openehr2bff/in`](openehr2bff/in) | `openehr2bff/out`, `openehr2pxf/out` |

Some output routes intentionally reuse the canonical input from another fixture
directory. The exact commands maintained by the test suite are in
[`t/19-cli-regression.t`](19-cli-regression.t).

## Run the Suite

```bash
prove -lr t
```

The active suite generates a small indexed OHDSI database from
[`fixtures/ohdsi-concepts.tsv`](fixtures/ohdsi-concepts.tsv). This keeps exact
ontology lookup and OMOP-output tests deterministic without requiring the
optional 2.2 GB database. Tests that exercise the complete Athena database
remain under `xt/`.

For a faster local run on machines with several CPU cores:

```bash
prove -j4 -lr t
```

Generated files are written to temporary directories by the tests. Do not
replace files under `t/*/out/` unless a deliberate conversion change has been
reviewed and the expected structure has changed.
