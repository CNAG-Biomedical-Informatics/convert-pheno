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

## Shared SDTM Semantics

The field-level BFF mapping is shared with Dataset-JSON:

| SDTM domain | Main BFF target |
| --- | --- |
| `DM` | id, sex, ethnicity, geographic origin, birth date, and vital status |
| `MH` | diseases |
| `AE` | phenotypic features |
| `LB`, `VS` | measures |
| `CM`, `EX` | treatments |
| `PR` | interventions or procedures |
| `TS` | synthesized dataset and cohort metadata |

See [Dataset-JSON to BFF](datasetjson2bff) for the detailed SDTM variable table.
The difference is the transport and provenance boundary, not the semantic
mapping.

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
