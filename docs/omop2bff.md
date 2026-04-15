!!! Note "OMOP to BFF - Schemas"
    * [OMOP CDM v5.4 tables](https://ohdsi.github.io/CommonDataModel/cdm54.html)
    * [Beacon v2 Models - individuals](https://docs.genomebeacons.org/schemas-md/individuals_defaultSchema)
    * [Beacon v2 Models - biosamples](https://docs.genomebeacons.org/schemas-md/biosamples_defaultSchema)

!!! Info "Information"
     The Beacon v2 schema enforces the presence of specific properties to achieve successful validation. In cases where no suitable match is found, DEFAULT values are employed to guarantee conformity.

     OMOP `SPECIMEN` rows can now be emitted as first-class Beacon `biosamples`, but only in entity-aware BFF mode such as `-obff --entities biosamples --out-dir out/` or `-obff --entities individuals biosamples --out-dir out/`.

     OMOP `SPECIMEN` to Beacon `biosamples` support should still be considered **experimental**. The mapping is implemented and covered by local tests and schema validation, but it is still pending review and validation with external collaborators.

     With `--stream`, OMOP BFF output is written as line-delimited JSON suitable for MongoDB-style ingestion. Stream mode supports `individuals`, `biosamples`, or both together, each written to its own file in `--out-dir`. Aggregate entities such as `datasets` and `cohorts` are not available in stream mode.

     If `biosamples` are explicitly requested and the OMOP input does not contain the `SPECIMEN` table, the conversion fails with a focused error. If `SPECIMEN` exists but is empty, the conversion succeeds and emits an empty `biosamples` collection.

--8<-- "tbl/mapping-omop2bff.md"

!!! Hint "About `exposures`"
    `exposures` terms are obtained from this [CSV file](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/share/db/concepts_candidates_2_exposure.csv). You can use a different csv file with the option `--exposures-file`.
