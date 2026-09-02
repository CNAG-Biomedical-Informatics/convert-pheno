---
title: PCORnet CDM to BFF
sidebar_label: PCORnet to BFF
---

:::warning[Mapping status]
Tests cover the PCORnet CDM table profile with synthetic fixtures.
Network-specific extensions may require additional mapping review.
:::

The route joins supported clinical tables to `DEMOGRAPHIC` by `PATID` and
creates one BFF `individuals` record per patient.

## Patient

| PCORnet source | BFF target | Behavior |
| --- | --- | --- |
| `DEMOGRAPHIC.PATID` | `id` | Required and unique |
| `SEX`, fallback `SEX_AT_BIRTH`, `GENDER` | `sex` | Male, female, other, and unknown values use Beacon-compatible defaults |
| `BIRTH_DATE`, fallback `BIRTHDATE`, `DATE_OF_BIRTH` | `info.phenopacket.dateOfBirth` | Supported dates become UTC timestamps for later PXF conversion |
| `ETHNICITY`, `ETHNIC`, or `HISPANIC` | `ethnicity` | Retained as a source-derived PCORnet term; common Hispanic indicators receive readable labels |
| `DEATH.DEATH_DATE`, fallback `DOD`, `DATE_OF_DEATH` | `info.phenopacket.vitalStatus` | A death row sets `DECEASED`; a supported date becomes `timeOfDeath.timestamp` |
| `RACE` | source provenance only | Race is not interpreted as Beacon ethnicity |

## Diagnoses And Procedures

| PCORnet source | BFF target | Behavior |
| --- | --- | --- |
| `DIAGNOSIS.DX`, fallback diagnosis code fields | `diseases[].diseaseCode` | `DX_TYPE` or equivalent identifies a recognized code system when possible |
| `CONDITION.CONDITION`, fallback condition code fields | `diseases[].diseaseCode` | Uses condition type and label fields when supplied |
| `PROCEDURES.PX`, fallback procedure code fields | `interventionsOrProcedures[].procedureCode` | Procedure type and label fields are retained |
| `IMMUNIZATION.VX_CODE` | `interventionsOrProcedures[].procedureCode` | Vaccine type and display fields are retained |
| procedure or administration date | `interventionsOrProcedures[].dateOfProcedure` | First supported `PX_DATE`, `PROCEDURE_DATE`, `VX_DATE`, or `ADMIN_DATE` is used |

## Measurements And Features

| PCORnet source | BFF target | Behavior |
| --- | --- | --- |
| `LAB_RESULT_CM.LAB_LOINC` | `measures[].assayCode` | Uses `LOINC:`; laboratory name fields supply the label |
| laboratory name or test code without LOINC | `measures[].assayCode` | Retained as a source-derived PCORnet laboratory term |
| numeric result and unit | `measurementValue.quantity` | Numeric value, unit, and complete low/high reference range are retained |
| qualitative or text result | categorical `measurementValue` | Used when no numeric result is available |
| `VITAL` height, weight, BMI, systolic, diastolic | `measures[]` | Uses built-in LOINC assay codes and retains supplied values and units |
| `OBS_CLIN` code and result | `measures[]` | Numeric or categorical clinical observation is retained |
| `OBS_GEN` code | `phenotypicFeatures[].featureType` | Type and label fields are retained when supplied |

## Treatments

| PCORnet source | BFF target | Behavior |
| --- | --- | --- |
| `PRESCRIBING`, `DISPENSING`, `MED_ADMIN`, `EXTERNAL_MEDS` | `treatments[]` | One treatment is emitted for each row with a usable code |
| `RXNORM_CUI`, fallback `RXCUI` | `treatmentCode` | Uses `RxNorm:` |
| `NDC` | `treatmentCode` | Uses `NDC:` |
| generic medication code and type | `treatmentCode` | A recognized type selects the prefix; otherwise a source-derived PCORnet term is used |
| route fields | `routeOfAdministration` | Retained as a source-derived PCORnet term |

## Encounter Context

`ENCOUNTERID`, `ENCOUNTER_NUM`, or `VISIT_ID` links a clinical row to
`ENCOUNTER`. Convert-Pheno attaches available dates and encounter type to the
mapped event through the private `_visit` extension. `_visit` is not a native
Beacon v2 or Phenopackets property.

## Terminology And Provenance

Recognized type values map to ICD-9-CM, ICD-10-CM, ICD-10-PCS, ICD-11, SNOMED
CT, LOINC, RxNorm, NDC, CVX, CPT-4, or HCPCS prefixes. Existing CURIEs are
retained. Ambiguous values receive a `PCORnet:` source identifier rather than
an unverified ontology assignment.

By default, source rows are copied to `info.pcornet`. Use `--no-source-info` to
omit this raw copy. For OMOP output, the second conversion stage resolves
supported terms against Athena-OHDSI; use `--term-audit` to inspect the result.

See the [PCORnet CDM format guide](pcornet) for accepted packages, commands,
and memory behavior.
