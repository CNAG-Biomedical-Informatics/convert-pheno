# CDISC Dataset-XML fixture provenance

The files in this directory are project-authored synthetic fixtures. They were
created for Convert-Pheno and were not downloaded from a remote dataset.

`define.xml` describes the synthetic `DM`, `MH`, `LB`, and `TS` domains using
Define-XML 2.0 metadata. The corresponding Dataset-XML 1.0 files reproduce a
subset of the synthetic study in `t/datasetjson2bff/in/`, expressed through
ODM 1.3.2 `ItemGroupData` and `ItemData` elements. They exercise participant
grouping, typed values, omitted missing values, study metadata, and the shared
SDTM-to-BFF mapping.

The fixture follows the published [CDISC Dataset-XML
v1.0](https://www.cdisc.org/standards/foundational/dataset-xml/dataset-xml-v10)
and [Define-XML
v2.0](https://www.cdisc.org/standards/data-exchange/define-xml/define-xml-v2-0)
specifications. It contains no real participant or study data.
