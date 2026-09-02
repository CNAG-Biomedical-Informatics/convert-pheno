---
title: i2b2 to BFF
sidebar_label: i2b2 to BFF
---

:::warning[Mapping status]
Tests cover the i2b2 star-schema profile with synthetic fixtures. Local
ontologies and dimension conventions may differ between installations.
:::

The route groups `PATIENT_DIMENSION`, `OBSERVATION_FACT`, and optional context
tables by `PATIENT_NUM`. It creates one BFF `individuals` record per patient.

## Patient

| i2b2 source | BFF target | Behavior |
| --- | --- | --- |
| `PATIENT_DIMENSION.PATIENT_NUM` | `id` | Required and unique |
| `SEX_CD`, fallback `SEX`, `GENDER_CD`, `GENDER` | `sex` | Male, female, other, and unknown values use Beacon-compatible defaults |
| `BIRTH_DATE`, fallback `BIRTHDATE`, `DATE_OF_BIRTH` | `info.phenopacket.dateOfBirth` | Supported dates become UTC timestamps for later PXF conversion |
| `DEATH_DATE`, fallback `DEATH_DATE_TIME`, `DOD` | `info.phenopacket.vitalStatus` | Sets `DECEASED` and retains `timeOfDeath.timestamp` |

## Observation Facts

| i2b2 source rule | BFF target | Behavior |
| --- | --- | --- |
| numeric `VALTYPE_CD=N` or a `LOINC:` concept | `measures[]` | `CONCEPT_CD` becomes `assayCode`; numeric or text result becomes `measurementValue` |
| ICD-9, ICD-10, ICD-11, SNOMED, or `DX` prefix | `diseases[].diseaseCode` | Prefix matching is case-insensitive and punctuation-normalized |
| CPT, HCPCS, ICD procedure, `PROC`, or `PX` prefix | `interventionsOrProcedures[].procedureCode` | `START_DATE` or `OBS_DATE` also becomes `dateOfProcedure` |
| RxNorm, NDC, `MED`, `MEDICATION`, or `DRUG` prefix | `treatments[].treatmentCode` | The coded observation becomes a treatment |
| any other coded fact | `phenotypicFeatures[].featureType` | Preserves the source concept rather than guessing its clinical category |
| non-`@` `MODIFIER_CD` | source provenance only | Modifier rows are not emitted as duplicate clinical events |

When `CONCEPT_DIMENSION` is supplied, `NAME_CHAR`, `CONCEPT_NAME`, `NAME`, or
`DESCRIPTION` supplies the term label for a matching `CONCEPT_CD`. Otherwise,
the code is also used as its label.

## Measurements

| i2b2 source | BFF target | Behavior |
| --- | --- | --- |
| `NVAL_NUM`, fallback `NUMERIC_VALUE` | `measurementValue.quantity.value` | Retained as a JSON number |
| `UNITS_CD`, fallback `UNIT` | `measurementValue.quantity.unit` | Retained as an `i2b2:Unit.*` source term |
| `TVAL_CHAR`, fallback `TEXT_VALUE` | categorical `measurementValue` | Used when no numeric result is available |
| `START_DATE`, fallback `OBS_DATE` | `measures[].date` | Supported date component is retained |

## Visit Context

`ENCOUNTER_NUM`, `ENCOUNTERID`, or `VISIT_ID` links a fact to
`VISIT_DIMENSION`. Convert-Pheno attaches the encounter identifier, optional
start and end timestamps, and visit type to the mapped event through the
private `_visit` extension. `_visit` preserves encounter relationships in BFF
but is not a native Beacon v2 or Phenopackets property.

## Terminology And Provenance

Existing CURIE-like `CONCEPT_CD` values are retained, with known prefixes
normalized where possible. Local or unrecognized identifiers remain
source-derived i2b2 terms; Convert-Pheno does not infer an external ontology
crosswalk.

By default, the source patient row and patient-scoped table rows are copied to
`info.i2b2`. Use `--no-source-info` to omit this raw copy. For OMOP output, the
second conversion stage resolves supported terms against the Athena-OHDSI
vocabulary; use `--term-audit` to review each resolution and fallback.

See the [i2b2 format guide](i2b2) for accepted packages, commands, and memory
behavior.
