---
title: FHIR to BFF
sidebar_label: FHIR to BFF
---

:::warning[Mapping status]
This table documents the experimental FHIR R4 JSON Bundle profile introduced
in **v0.33**. Its current coverage reflects the resources and fixture described
below and may be refined as additional FHIR implementations and profiles are
evaluated.

Parts of the mapping were drafted or refined with LLM assistance using
**GPT-5.6 Sol** with **ultra reasoning**, followed by human review, regression
testing, and target-format validation.
:::

The route resolves Bundle references, groups resources by Patient, creates one
Beacon `individuals` record per Patient, and can emit first-class `biosamples`
plus source-derived `datasets` and `cohorts`.

## Patient

| FHIR source | BFF target | Behavior |
| --- | --- | --- |
| `Patient.id`, fallback `Patient.identifier[].value` | `id` | A stable identifier is required |
| `Patient.gender` | `sex` | Supported FHIR administrative gender values use Beacon-compatible NCIT defaults; unsupported or absent values use unknown sex |
| `Patient.birthDate` | `info.phenopacket.dateOfBirth` | A full date becomes a UTC midnight timestamp for later PXF conversion |
| `Patient.deceasedDateTime` | `info.phenopacket.vitalStatus` | Sets `DECEASED` and retains `timeOfDeath.timestamp` |
| `Patient.deceasedBoolean` | `info.phenopacket.vitalStatus.status` | Maps to `DECEASED` or `ALIVE` |
| US Core ethnicity extension | `ethnicity` | Uses the extension coding and display/text when present |
| `patient-birthPlace` extension | `geographicOrigin` | Two- or three-letter country values use `ISO3166-1:`; other values use a source-derived FHIR term |

## Conditions And Phenotypic Features

| FHIR source | BFF target | Behavior |
| --- | --- | --- |
| `Condition.code` | `diseases[].diseaseCode` | First usable coding is retained as an ontology term; text is the fallback |
| `Condition.onsetDateTime` | `diseases[].ageOfOnset` | Becomes age when `Patient.birthDate` is available, otherwise a timestamp |
| `Condition.abatementDateTime` | `diseases[].resolution` | Becomes age when possible, otherwise a timestamp |
| refuted or entered-in-error `Condition.verificationStatus` | `diseases[].excluded` | Sets `true` |
| HPO coding in `Observation.code` or `Observation.valueCodeableConcept` | `phenotypicFeatures[].featureType` | Recognized by the `HP:` CURIE prefix |
| `Observation.valueBoolean=false` for an HPO feature | `phenotypicFeatures[].excluded` | Sets `true`; other cases set `false` |
| HPO Observation effective date | `phenotypicFeatures[].onset` | Becomes age when possible, otherwise a timestamp |

## Measurements

| FHIR source | BFF target | Behavior |
| --- | --- | --- |
| `Observation.code` | `measures[].assayCode` | Maps the assay coding or text |
| `Observation.component[]` | additional `measures[]` | Each component with a usable code and value becomes a separate measure |
| `valueQuantity` | `measurementValue.quantity` | Numeric value and coded/display unit are retained |
| `referenceRange[].low/high` | `measurementValue.quantity.referenceRange` | Retained when both bounds are numeric |
| `valueCodeableConcept` | `measurementValue` | Retained as a categorical ontology term |
| `valueInteger`, `valueDecimal` | `measurementValue.quantity` | Numeric value is retained with a not-available unit fallback when no unit exists |
| `valueBoolean`, `valueString`, `valueCode`, `valueDateTime`, `valueDate` | `measurementValue` | Retained as a source-derived FHIR term |
| `Observation.effectiveDateTime`, period start, or `issued` | `measures[].date` | Date component is retained |
| `Observation.method` | `measures[].procedure.procedureCode` | Retained when coded or labeled |

An Observation with `specimen.reference` is not added to the individual's
`measures`. It is mapped to the matching biosample's `measurements` instead.

## Procedures And Treatments

| FHIR source | BFF target | Behavior |
| --- | --- | --- |
| `Procedure.code` | `interventionsOrProcedures[].procedureCode` | Coding or text is retained |
| `Procedure.performedDateTime`, fallback period start | `interventionsOrProcedures[].dateOfProcedure` | Date component is retained |
| first `Procedure.bodySite` | `interventionsOrProcedures[].bodySite` | Coding or text is retained |
| medication code or resolvable `medicationReference` | `treatments[].treatmentCode` | Supports `MedicationRequest`, `MedicationAdministration`, and `MedicationStatement`, including contained Medication resources |
| first applicable dosage route | `treatments[].routeOfAdministration` | Coding or text is retained |
| authored/effective start | `treatments[].ageOfOnset` | Becomes age when `Patient.birthDate` is available |

## Specimens And Biosamples

| FHIR source | BFF biosample target | Behavior |
| --- | --- | --- |
| `Specimen.id` | `id` | Required for first-class biosample output |
| resolved Patient | `individualId` | Uses the owning Patient id |
| `Specimen.status` | `biosampleStatus` | Retained as a source-derived FHIR term |
| `Specimen.type` | `sampleOriginType` | Coding or text is retained; missing values use the Beacon ontology-term default |
| `Specimen.collection.collectedDateTime` | `collectionDate` | Date component is retained |
| `Specimen.collection.bodySite` | `sampleOriginDetail` | Coding or text is retained |
| `Specimen.collection.method` | `obtentionProcedure.procedureCode` | Coding or text is retained |
| `Specimen.note[].text` | `notes` | Multiple notes are joined with newlines |
| linked `Observation` resources | `measurements[]` | Uses the same measurement mapping and requires a resolvable `Observation.specimen` reference |

The semantic biosample representation is also retained under
`individuals[].info.phenopacket.biosamples`. This is deliberate: it allows the
`fhir2pxf` pipeline to preserve specimen data while the pipeline's primary BFF
view carries individuals between stages.

## Study Metadata

| FHIR source | BFF entity metadata | Behavior |
| --- | --- | --- |
| first `ResearchStudy.id` or identifier | dataset id | Falls back to the first Bundle id or a generated source id |
| `ResearchStudy.title`, fallback name | dataset name | Falls back to the dataset id |
| `ResearchStudy.description` | dataset description | Retained when scalar |
| first `Group.id` or identifier | cohort id | Used for the source-derived cohort |
| `Group.name` | cohort name | Falls back to the cohort id |
| `Group.quantity`, fallback member count | cohort size | Retained as a number |

Explicit `derived_entity_overrides` supplied through a programmatic request take
precedence over this source-derived metadata.

## Terminology And Provenance

Known coding-system URIs map to stable prefixes including `HP`, `LOINC`,
`SNOMEDCT`, `RxNorm`, `UCUM`, `NCIT`, and ICD-10 variants. Existing CURIE codes
are retained. Whitespace in identifiers is replaced with `_` for API-safe
identifiers.

Unknown coding systems receive a prefix derived from the system URI, and
uncoded text receives a `FHIR:` source identifier. These values preserve source
identity and are not evidence of ontology resolution.

By default, raw Patient and patient-scoped resources are copied under
`info.fhir`; biosamples retain their source Specimen and linked Observations.
`--no-source-info` removes those copies while retaining mapped BFF fields and
semantic Phenopacket biosample data.

## Current Boundaries

The current profile does not read FHIR XML, Bulk Data NDJSON, or live FHIR
server endpoints. Resources without an implemented first-class mapping remain
in provenance. Arbitrary extensions, profile-specific slices, encounter-level
grouping, and terminology-server expansion are outside the current mapper.

See the [FHIR R4 guide](fhir) for input constraints, commands, interface
availability, and memory behavior.
