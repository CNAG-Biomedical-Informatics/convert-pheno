---
title: Dataset-XML to BFF
sidebar_label: Dataset-XML to BFF
---

:::warning[Mapping status]
Dataset-XML v1.0 with Define-XML v2.x support was added for **v0.34**. The
fixtures cover the parser and documented mappings, but not every study or XML
generator.
:::

Dataset-XML is first resolved against Define-XML, then passed to the same SDTM
semantic mapper used by Dataset-JSON. It creates one BFF `individuals` record
per `DM.USUBJID` and can synthesize `datasets` and `cohorts`.

## Transport Resolution

| Dataset-XML / Define-XML source | Normalized content | Behavior |
| --- | --- | --- |
| `ClinicalData` or `ReferenceData` `StudyOID` and `MetaDataVersionOID` | study metadata selector | Must resolve to exactly one Define-XML metadata version |
| `ItemGroupData.ItemGroupOID` | SDTM domain | Must resolve to one Define-XML `ItemGroupDef`; one group is accepted per file |
| ordered `ItemGroupDef.ItemRef` | domain columns | Supplies column identity and order |
| referenced `ItemDef.Name` | SDTM variable name | Used as the normalized row key |
| referenced `ItemDef.DataType` | scalar type | Integer, decimal, float, double, and boolean values are coerced; other supported values remain strings |
| `ItemDef.CodeListRef` and decoded text | source terminology metadata | Supplies the source display for controlled values |
| `Alias Context="nci:ExtCodeID"` | NCIT identifier | Resolved by exact identifier lookup to obtain the canonical NCIT display |
| `ItemGroupDataSeq` | source row number | Must be present and unique within the file |
| `ItemData.ItemOID` and `Value` | row value | Unknown or duplicate item identifiers fail; omitted `ItemData` means missing |

## Demographics

After Define-XML resolves the variable names, the following mappings apply.
Targets are relative to one BFF individual. Dataset-JSON uses the same mapper.

| SDTM source | BFF target | Notes |
| --- | --- | --- |
| `DM.USUBJID` | `id` | Required; one `DM` row per participant |
| `DM.SEX` | `sex` | Male, female and other use NCIT terms; missing or unrecognized values use unknown |
| `DM.ETHNIC` | `ethnicity` | Uses terminology resolution described below |
| `DM.COUNTRY` | `geographicOrigin` | Without a resolved term, two- or three-letter values receive an `ISO3166-1:` prefix; other values use a source-derived term |
| `DM.BRTHDTC` | `info.phenopacket.dateOfBirth` | Full dates become midnight UTC; supported timestamps are retained |
| `DM.DTHFL=Y` or a supplied `DM.DTHDTC` | `info.phenopacket.vitalStatus.status` | Sets `DECEASED` |
| `DM.DTHDTC` | `info.phenopacket.vitalStatus.timeOfDeath.timestamp` | Included when the date or timestamp is supported |

## Diseases And Phenotypic Features

| SDTM source | BFF target | Notes |
| --- | --- | --- |
| `MH.MHDECOD`, fallback `MH.MHTERM` | `diseases[].diseaseCode` | Reported `MHTERM` is preferred for the source label |
| `AE.AEDECOD`, fallback `AE.AETERM` | `phenotypicFeatures[].featureType` | Reported `AETERM` is preferred for the source label; `excluded` is `false` |
| `AE.AESEV` | `phenotypicFeatures[].severity` | Included when supplied |
| `AE.AESTDTC` | `phenotypicFeatures[].onset.timestamp` | Supported date or timestamp |
| `AE.AEENDTC` | `phenotypicFeatures[].resolution.timestamp` | Supported date or timestamp |

## Measurements

Each usable laboratory or vital-sign row becomes a measure.

| SDTM source | BFF target | Notes |
| --- | --- | --- |
| `LB.LBTESTCD`, fallback `LB.LBTEST` | `measures[].assayCode` | `LBTEST` supplies the preferred source label |
| `VS.VSTESTCD`, fallback `VS.VSTEST` | `measures[].assayCode` | `VSTEST` supplies the preferred source label |
| `LB.LBSTRESN` or `VS.VSSTRESN` | `measures[].measurementValue.quantity.value` | Used when numeric |
| `LB.LBSTRESU` or `VS.VSSTRESU` | `measures[].measurementValue.quantity.unit` | Missing units default to `NCIT:C126101` / `Not Available` |
| `LB.LBSTNRLO/LBSTNRHI` or `VS.VSSTNRLO/VSSTNRHI` | `measures[].measurementValue.quantity.referenceRange` | Both bounds must be numeric; uses the measurement unit |
| `LB.LBSTRESC` or `VS.VSSTRESC` | `measures[].measurementValue` | Categorical term when no numeric result is available; rows without either result are skipped |
| `LB.LBDTC` or `VS.VSDTC` | `measures[].date` | Date component only |

## Treatments And Procedures

| SDTM source | BFF target | Notes |
| --- | --- | --- |
| `CM.CMDECOD`, fallback `CM.CMTRT` | `treatments[].treatmentCode` | `CMTRT` supplies the preferred source label |
| `EX.EXTRT` | `treatments[].treatmentCode` | Exposure treatment |
| `CM.CMROUTE` or `EX.EXROUTE` | `treatments[].routeOfAdministration` | Included when supplied |
| `PR.PRDECOD`, fallback `PR.PRTRT` | `interventionsOrProcedures[].procedureCode` | `PRTRT` supplies the preferred source label |
| `PR.PRLOC` | `interventionsOrProcedures[].bodySite` | Included when supplied |
| `PR.PRSTDTC` | `interventionsOrProcedures[].dateOfProcedure` | Date component only |

Other fields, including treatment doses and medical-history dates, remain in
source provenance rather than being mapped to dedicated BFF fields.

## Study Metadata

These defaults are used when dataset or cohort output is requested.

| Source | BFF target | Notes |
| --- | --- | --- |
| XML `StudyOID` | Dataset `id`; cohort `id` | Cohort identifier adds `-cohort` |
| `TS.TSVAL` where `TS.TSPARMCD=TITLE` | Dataset and cohort `name` | Falls back to `StudyOID` |
| `StudyOID` | Dataset `description` | Generated description identifying the Dataset-XML study |
| Built-in value | Cohort `cohortType` | `study-defined` |
| XML metadata and subject-independent domains | Dataset `info.datasetXml` | Omitted with `--no-source-info` |

## Terminology And Provenance

Mapped rows are retained under `info.datasetXml.domains`. Transport metadata
includes `datasetXMLVersion`, `defineXMLVersion`, `studyOID`,
`metaDataVersionOID`, and the Define reference when supplied. Unmapped subject
domains are named in `info.datasetXml.unmappedDomains`.

Supported NCI identifiers from Define-XML take precedence over mapping-file
queries and are always looked up exactly. An optional Mapping V2 file with
`source.profile: sdtm` can supply direct terms or reviewed label queries for
other term-bearing fields. When neither source metadata nor the mapping
resolves a term, source-derived `CDISC:` identifiers preserve SDTM field/value
identity without claiming an ontology crosswalk.

Use `--term-audit` to distinguish Define-XML identifiers, direct mapping
terms, database matches, and source fallbacks. Use `--no-source-info` to omit
the raw rows. See [Terminology Search](terminology-search) for the complete
resolution contract.

Paired [baseline](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/t/datasetxml2bff/out/individuals.json)
and [terminology](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/t/datasetxml2bff/out/terminology/individuals.json)
references show that these outcomes are separate, tested code paths.

See the [Dataset-XML guide](dataset-xml) for commands, required files, and
memory behavior.
