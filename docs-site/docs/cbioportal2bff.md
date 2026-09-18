---
title: cBioPortal to BFF
sidebar_label: cBioPortal to BFF
---

The tables describe the built-in mapping. Target paths are relative to one
record in the named BFF collection. An optional mapping file can add or replace
mapped fields as described below.

## Individuals

One individual is created per `PATIENT_ID`. If the patient table is absent,
patient identifiers are taken from the sample table.

| Source field | BFF target | Notes |
| --- | --- | --- |
| Patient `PATIENT_ID` | `id` | Required; optional mapping cannot change it |
| Patient `SEX`, fallback `GENDER` | `sex` | First non-empty value; male, female and other use NCIT defaults, otherwise unknown |
| Patient `OS_STATUS` | `info.phenopacket.vitalStatus.status` | Values containing `DECEASED` become `DECEASED`; `LIVING` or `ALIVE` become `ALIVE`; otherwise omitted |
| Linked samples' `ONCOTREE_CODE` | `diseases[].diseaseCode.id` | `OncoTree:` prefix; one entry per distinct code within the patient |
| Sample `CANCER_TYPE_DETAILED`, fallback `CANCER_TYPE`, then OncoTree code | `diseases[].diseaseCode.label` | Requires a usable `ONCOTREE_CODE`; a cancer label alone does not create a disease |
| Patient row | `info.cbioportal.patient` | Original columns, unless `--no-source-info` |
| Linked biosamples | `info.phenopacket.biosamples[]` | Phenopackets representation retained for subsequent PXF conversion |

## Biosamples

| Source field | BFF target | Notes |
| --- | --- | --- |
| Sample `SAMPLE_ID` | `id` | Required and unique |
| Sample `PATIENT_ID` | `individualId` | Links to the corresponding individual |
| Sample `ONCOTREE_CODE` | `histologicalDiagnosis.id` | `OncoTree:` prefix; omitted when the code is absent or marked unavailable |
| Sample `CANCER_TYPE_DETAILED`, fallback `CANCER_TYPE`, then OncoTree code | `histologicalDiagnosis.label` | Same label selection as individual diseases |
| No built-in source mapping | `biosampleStatus`, `sampleOriginType` | Both default to `NCIT:C126101` / `Not Available` |
| Sample `SAMPLE_TYPE` | `info.cbioportal.sample.SAMPLE_TYPE` | Source value only; not automatically converted into an ontology term |
| Sample row | `info.cbioportal.sample` | Original columns, unless `--no-source-info` |

## Datasets

One dataset is emitted for the study when `datasets` is requested.

| Source field | BFF target | Notes |
| --- | --- | --- |
| Study metadata `cancer_study_identifier` | `id` | Source-derived default |
| Study metadata `name` | `name` | Required in the study package |
| Study metadata `description` | `description` | Falls back to “cBioPortal study” followed by the study identifier |
| Number of patients and samples | `info.individualCount`, `info.biosampleCount` | Counts across the study |
| Study metadata | `info.cbioportal.study` | Unless `--no-source-info` |
| Patient and sample column definitions | `info.cbioportal.patientAttributeDefinitions`, `info.cbioportal.sampleAttributeDefinitions` | Unless `--no-source-info` |

## Cohorts

One cohort is emitted per case list when `cohorts` is requested.

| Source field | BFF target | Notes |
| --- | --- | --- |
| Case-list `stable_id` | `id` | Preserved |
| Case-list `case_list_name` | `name` | Preserved |
| Built-in value | `cohortType` | `study-defined` |
| Case-list `case_list_ids` | `info.cbioportal.membership.sampleIds` | Sample identifiers; unknown samples cause an error |
| Patients linked to those samples | `info.cbioportal.membership.individualIds` | Distinct patient identifiers |
| Number of distinct linked patients | `cohortSize` | Counts people, not samples |
| Case-list metadata | `info.cbioportal.caseList` | Unless `--no-source-info`; membership is always retained |

## Required Defaults

BFF requires ontology terms for `biosampleStatus` and `sampleOriginType`.
cBioPortal clinical tables do not guarantee ontology identifiers for either
field, so the built-in mapping uses `NCIT:C126101` (`Not Available`). An
optional mapping may replace these defaults with curated terms.

The source value `SAMPLE_TYPE=Primary` is not mapped to the generic NCIT term
whose label is also “Primary.” Label equality alone does not establish that a
source category represents specimen origin.

## Source Provenance

With the default `--source-info`, generated records retain:

- patient attributes under `info.cbioportal.patient`
- sample attributes under `info.cbioportal.sample`
- study and attribute-definition metadata under dataset `info.cbioportal`
- case-list descriptors and resolved membership under cohort `info.cbioportal`

`--no-source-info` removes copied source payloads. Resolved cohort membership
is retained because it is part of the converted relationship graph.

## Optional Mapping

Use `source.profile: cbioportal`. Individual rules read patient columns and
biosample rules read sample columns. Dataset and cohort defaults can augment
the source-derived collection metadata. Patient and sample identifiers and their
links cannot be changed. Dataset defaults can override dataset metadata; cohort
`id`, `name`, and `cohortSize` remain derived from the case list.

See the [cBioPortal format guide](cbioportal) for commands and input scope.
