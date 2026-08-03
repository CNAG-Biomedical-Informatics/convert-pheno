---
title: Dataset-JSON to BFF
sidebar_label: Dataset-JSON to BFF
---

:::warning[Mapping status]
This table documents the experimental Dataset-JSON v1.1 SDTM profile introduced
in **v0.33**. Its current coverage reflects the domains and fixtures described
below and may be refined as additional study datasets and SDTM profiles are
evaluated.
:::

This table records the implemented CDISC Dataset-JSON v1.1 SDTM mapping. The
route groups domain rows by `USUBJID`, creates one Beacon `individuals` record
per `DM` participant, and can synthesize `datasets` and `cohorts` from study
metadata.

The structural targets below are built in. Term-bearing fields can be enriched
through the optional SDTM terminology mapping described under
[Terminology And Provenance](#terminology-and-provenance).

## Demographics

| SDTM source | BFF target | Behavior |
| --- | --- | --- |
| `DM.USUBJID` | `id` | Required and unique within `DM` |
| `DM.SEX` | `sex` | `M`, `F`, and `UNDIFFERENTIATED`/`OTHER` use Beacon-compatible NCIT terms; other values use the unknown-sex default |
| `DM.ETHNIC` | `ethnicity` | Retained as a source-derived CDISC term |
| `DM.COUNTRY` | `geographicOrigin` | Two- or three-letter values use `ISO3166-1:`; other values use a source-derived CDISC term |
| `DM.BRTHDTC` | `info.phenopacket.dateOfBirth` | A date becomes a UTC midnight timestamp; supported timestamps are retained |
| `DM.DTHFL`, `DM.DTHDTC` | `info.phenopacket.vitalStatus` | `Y` or a death date sets `DECEASED`; a supported death date also becomes `timeOfDeath.timestamp` for later PXF conversion |

## Clinical Domains

| SDTM source | BFF target | Behavior |
| --- | --- | --- |
| `MH.MHDECOD`, fallback `MH.MHTERM` | `diseases[].diseaseCode` | Reported term is preferred as the label |
| `AE.AEDECOD`, fallback `AE.AETERM` | `phenotypicFeatures[].featureType` | Adverse events are emitted with `excluded: false` |
| `AE.AESEV` | `phenotypicFeatures[].severity` | Retained as a source-derived CDISC term |
| `AE.AESTDTC`, `AE.AEENDTC` | `phenotypicFeatures[].onset`, `.resolution` | Supported values become timestamp time elements |
| `LB.LBTESTCD`, fallback `LB.LBTEST` | `measures[].assayCode` | `LBTEST` is preferred as the label |
| `VS.VSTESTCD`, fallback `VS.VSTEST` | `measures[].assayCode` | `VSTEST` is preferred as the label |
| `LB/VS.STRESN`, `.STRESU` | `measures[].measurementValue.quantity` | Numeric value and unit are retained; `LB.STNRLO/STNRHI` become the reference range when both are numeric |
| `LB/VS.STRESC` | `measures[].measurementValue` | Used as a categorical ontology term when no numeric result is available |
| `LB.LBDTC`, `VS.VSDTC` | `measures[].date` | Date component is retained |
| `CM.CMDECOD`, fallback `CM.CMTRT` | `treatments[].treatmentCode` | Reported treatment is preferred as the label |
| `EX.EXTRT` | `treatments[].treatmentCode` | Exposure treatment is retained as a source-derived term |
| `CM.CMROUTE`, `EX.EXROUTE` | `treatments[].routeOfAdministration` | Route is retained as a source-derived term |
| `PR.PRDECOD`, fallback `PR.PRTRT` | `interventionsOrProcedures[].procedureCode` | Reported procedure is preferred as the label |
| `PR.PRLOC`, `PR.PRSTDTC` | procedure body site and date | Body site becomes a source-derived term; supported dates are retained |

## Study Metadata

| Dataset-JSON source | BFF entity metadata | Behavior |
| --- | --- | --- |
| `studyOID` | dataset id and cohort id | Cohort id receives a `-cohort` suffix |
| `TS.TSPARMCD=TITLE` and `TS.TSVAL` | dataset and cohort name | Falls back to `studyOID` when no title is supplied |
| Dataset metadata and subject-independent domains | `datasets[].info.datasetJson` | Included unless `--no-source-info` is used |

## Terminology And Provenance

Term-bearing SDTM fields use the following precedence:

1. A curated mapping `term` or matching entry in `terms`
2. A supported NCI identifier from optional Define-XML metadata
3. A mapping-file label query, including reviewed aliases
4. A source-derived CDISC term

The compact mapping uses `source.profile: sdtm` and a top-level `terminology`
object keyed by `DOMAIN.FIELD`. Structural SDTM-to-BFF fields are not
redeclared. In an alias such as `MILD_GRADE: Mild`, the left side is a local
source value and the right side is the database label selected by the data
owner. Aliases are selective; values that already match a database label do
not need to be listed.

If no configured or source-authoritative resolution applies, field/value pairs
are encoded as source-derived CURIEs such as `CDISC:LBTESTCD.ALT` or
`CDISC:LBSTRESC.NEGATIVE`. Whitespace and punctuation are normalized for
API-safe identifiers. These fallbacks preserve source identity and are not
evidence of external terminology resolution.

Use `--term-audit` to review source values, labels, lookup inputs, emitted
terms, match provenance, and fallbacks. See [Terminology Search](terminology-search)
for the complete contract.

The checked-in references deliberately include both the [baseline fallback
output](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/t/datasetjson2bff/out/individuals.json)
and an [output using the reviewed terminology
mapping](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/t/datasetjson2bff/out/terminology/individuals.json).

All supplied subject-level rows are copied under `info.datasetJson.domains` by
default. Domains without a first-class mapping are also named in
`info.datasetJson.unmappedDomains`. `--no-source-info` removes this raw copy,
not the mapped fields.

The current first-class domain set is `DM`, `MH`, `AE`, `LB`, `VS`, `CM`, `EX`,
and `PR`. See the [Dataset-JSON guide](dataset-json) for input constraints,
commands, and memory behavior.
