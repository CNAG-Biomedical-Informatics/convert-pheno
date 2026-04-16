!!! Note "BFF to OMOP CDM - Schemas"
    * [Beacon v2 Models - individuals](https://docs.genomebeacons.org/schemas-md/individuals_defaultSchema)
    * [OMOP Common Data Model](https://ohdsi.github.io/CommonDataModel/)

!!! Info "Information"
    This table reflects the current `bff2omop` implementation in `convert-pheno`.
    The conversion maps one Beacon `individual` into OMOP `PERSON` and expands
    repeated Beacon fields into OMOP row arrays such as `CONDITION_OCCURRENCE`,
    `OBSERVATION`, `PROCEDURE_OCCURRENCE`, `MEASUREMENT`, and `DRUG_EXPOSURE`.

--8<-- "tbl/mapping-bff2omop.md"
