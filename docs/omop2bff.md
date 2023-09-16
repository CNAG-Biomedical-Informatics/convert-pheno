!!! Note "OMOP to BFF - Schemas"
    * [OMOP-CDM v5.4 tables](https://ohdsi.github.io/CommonDataModel/cdm54.html)
    * [Beacon v2 Models - individuals](https://docs.genomebeacons.org/schemas-md/individuals_defaultSchema)

!!! Info "Information"
     The Beacon v2 schema enforces the presence of specific properties to achieve successful validation. In cases where no suitable match is found, DEFAULT values are employed to guarantee conformity.

--8<-- "tbl/mapping-omop2bff.md"

!!! Hint "About `exposures`"
    `exposures` terms are obtained from this [CSV file](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/share/db/concepts_candidates_2_exposure.csv). You can use a different csv file with the option `--exposures-file`.

##### last change 2023-06-09 by Manuel Rueda [:fontawesome-brands-github:](https://github.com/mrueda)
