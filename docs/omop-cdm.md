**OMOP CDM** stands for **O**bservational **M**edical **O**utcomes **P**artnership **C**ommon **D**ata **M**odel. **OMOP CDM** [documentation](https://www.ohdsi.org/data-standardization/the-common-data-model).

<figure markdown>
   ![OMOP CDM](https://www.ohdsi.org/wp-content/uploads/2015/02/h243-ohdsi-logo-with-text.png){ width="400" }
   <figcaption>Image extracted from www.ohdsi.org</figcaption>
</figure>

The **OMOP CDM** is designed to be database-agnostic, which means it can be implemented using different relational database management systems, with **PostgreSQL** being a popular choice.

`Convert-Pheno` is capable of performing both **file-based conversions** (from PostgreSQL exports in `.sql` or from any other SQL database via `.csv` files) and **real-time conversions** (e.g., from [SQL queries](http://cdmqueries.omop.org)) as long as the data has been converted to the accepted JSON format.

`Convert-Pheno` supports `OMOP-CDM` in both directions:

- as **input**, from `.sql`, `.csv`, `.sql.gz`, or `.csv.gz` exports
- as **output**, as OMOP CSV tables generated from `BFF` input

??? Warning "About OMOP CDM longitudinal data"
    OMOP CDM stores `visit_occurrence_id` for each `person_id` in the `VISIT_OCCURRENCE table`. However, [Beacon v2 Models](https://docs.genomebeacons.org/schemas-md/individuals_defaultSchema) currently lack a way to store longitudinal data. To address this, we added a property named `_visit` to each record, which stores visit information. This property will be serialized only if the `VISIT_OCCURRENCE` table is provided.

!!! Tip "OMOP CDM supported version(s)"
    Currently, Convert-Pheno supports versions **5.3** and **5.4** of OMOP CDM, and its prepared to support v6 once we can test the code with v6 projects.

## OMOP As Output

`OMOP-CDM` can also be emitted as output from `BFF` input. In that direction, `Convert-Pheno` writes OMOP CSV tables rather than Beacon-style JSON.

Example:

```bash
convert-pheno -ibff individuals.json -oomop --out-dir omop_export/
```

This writes table files such as `omop_export/PERSON.csv`, `omop_export/CONDITION_OCCURRENCE.csv`, and related OMOP outputs.

To rename one of the emitted tables:

```bash
convert-pheno -ibff individuals.json -oomop --out-dir omop_export/ --out-name PERSON=patients.csv
```

## OMOP As Input

=== "Command-line"

    When using the `convert-pheno` command-line interface, simply ensure the [correct syntax](usage.md) is provided.

    !!! Note "Individuals-only vs entity-aware BFF output"
        Most examples below use the individuals-only `-obff FILE` path, which still emits Beacon `individuals` as one file. In non-stream BFF workflows, you can also request synthesized `datasets` and `cohorts` with `--entities ... --out-dir out/`. `biosamples` can now be emitted from OMOP `SPECIMEN`, but this OMOP-to-BFF biosample path is still experimental and pending validation with external collaborators.

    ??? Tip "Does `Convert-Pheno` accept `gz` files?"

        Yes, both input and output files can be **gzipped** to save space. However, it's important to note that the **gzip layer introduces an overhead**. 
        
        This overhead can be substantial, potentially doubling the processing time in `--stream` mode when handling PostgreSQL dumps as input.

    ???+ Danger "About `--max-lines-sql` default value"
        Please note that for **PostgreSQL dumps**, we have configured `--max-lines-sql=500` which is suitable for testing purposes. However, for real data, it is recommended to **increase this limit** to match the size of your largest table. This flag does not apply when your input files are `CSV`.

    === "Small to medium-sized files (<1M rows)"

        #### All tables at once

        Usage:

        ```
        convert-pheno -iomop omop_dump.sql -obff individuals.json
        ```
        or when gzipped...
        ```
        convert-pheno -iomop omop_dump.sql.gz -obff individuals.json.gz
        ```
        with multiple CSVs (one CSV per table)...
        ```
        convert-pheno -iomop *csv -obff individuals.json.gz
        ```

        #### Independent table files

        You can also provide **independent table files explicitly**, one file per OMOP table. This is useful when your export is already split by table, or when you only want to work with a reduced set of tables.

        For example:

        ```bash
        convert-pheno -iomop PERSON.csv CONCEPT.csv DRUG_EXPOSURE.csv -obff individuals.json
        ```

        To emit entity-aware `BFF` output instead:

        ```bash
        convert-pheno -iomop PERSON.csv CONCEPT.csv DRUG_EXPOSURE.csv -obff --entities individuals datasets cohorts --out-dir out/
        ```

        To emit Beacon `biosamples` from OMOP `SPECIMEN` without synthesized `datasets` or `cohorts`:

        ```bash
        convert-pheno -iomop PERSON.csv CONCEPT.csv SPECIMEN.csv -obff --entities biosamples --out-dir out/
        ```

        When `SPECIMEN.quantity` is present, `Convert-Pheno` also emits it as a
        sample-level `biosamples.measurements` entry. The value comes from
        `SPECIMEN.quantity`, the unit is resolved from `unit_concept_id` when
        available, and `unit_source_value` is used as a fallback label. Because
        OMOP `SPECIMEN` has no `measurement_concept_id` equivalent for this
        field, the Beacon `assayCode` uses the valid local CURIE
        `OMOP:SPECIMEN.quantity` with label `Specimen quantity`.

        By default, the original OMOP rows are also preserved under fields such
        as `info.PERSON.OMOP_columns` or
        `biosamples.info.SPECIMEN.OMOP_columns`. This is intentional: it helps
        users audit the mapping and, when desired, query original OMOP values
        through Beacon-oriented APIs. Use `--no-source-info` to omit these raw
        OMOP payloads from the generated `BFF`.

        In this mode, `Convert-Pheno` infers the OMOP table name from each filename. At minimum, practical conversions usually require:

        - `PERSON`
        - `CONCEPT` or `--ohdsi-db`
        - one or more clinical tables such as `DRUG_EXPOSURE`, `MEASUREMENT`, `OBSERVATION`, or `CONDITION_OCCURRENCE`

        The same approach also works with gzipped table files:

        ```bash
        convert-pheno -iomop PERSON.csv.gz CONCEPT.csv.gz DRUG_EXPOSURE.csv.gz -obff individuals.json.gz
        ```

        #### Selected table(s)

        It is possible to convert selected tables. For instance, in case you only want to convert `DRUG_EXPOSURE` table use the option `--omop-tables`. The option accepts a list of tables (case insensitive) separated by spaces:

        !!! Warning "About tables `CONCEPT` and `PERSON`"
            Tables `CONCEPT` and `PERSON` are always loaded as they're needed for the conversion. You don't need to specify them.

        ```
        convert-pheno -iomop omop_dump.sql -obff individuals.json --omop-tables DRUG_EXPOSURE
        ```

        Using this approach you will be able to submit multiple jobs in **parallel**.

        ??? Question  "What if my `CONCEPT` table does not contain all standard `concept_id`(s)"
            In this case, you can use the flag `--ohdsi-db` that will enable checking an internal database whenever the `concept_id` can not be found inside your `CONCEPT` table.

            ```
            convert-pheno -iomop omop_dump.sql -obff individuals_measurement.json --omop-tables DRUG_EXPOSURE --ohdsi-db
            ```

        ??? Danger "RAM memory usage in `--no-stream` mode (default)"
            When working with `-iomop` and `--no-stream`, `Convert-Pheno` will consolidate all the values corresponding to a given attribute `person_id` under the same object. In order to do this, we need to store all data in the **RAM** memory. The reason for storing the data in RAM is because the rows are **not adjacent** (they are not pre-sorted by `person_id`) and can originate from **distinct tables**.

            Number of rows | Estimated RAM memory | Estimated time
                   :---:   |   :---:              | :---:
                    100K   | <1GB                 | 5s
                    500K   | 1GB                  | 15s
                    1M     | 2GB                  | 30s
                    2M     | 4GB                  | 1m

             1 x Intel(R) Xeon(R) W-1350P @ 4.00GHz - 32GB RAM - SSD

            If your computer only has 4GB-8GB of RAM and you plan to convert **large files** we recommend you to use the flag `--stream` which will process your tables **incrementally** (i.e.,line-by-line), instead of loading them into memory. 

    === "Large files (>1M rows)"

        For large files, `Convert-Pheno` allows for a different approach. The files can be parsed incrementally (i.e., line-by-line).

        To choose incremental data processing we'll be using the flag `--stream`:

        ??? Danger " `--stream` mode supported output"
            We currently support only the individuals-only `BFF` path (`-obff FILE`) in `--stream` mode.

        #### All tables at once

        ```
        convert-pheno -iomop omop_dump.sql.gz -obff individuals.json.gz --stream
        ```

        You can also stream **independent OMOP table files** directly:

        ```bash
        convert-pheno -iomop PERSON.csv.gz CONCEPT.csv.gz DRUG_EXPOSURE.csv.gz -obff individuals.json.gz --stream --ohdsi-db
        ```

        !!! Warning "About OMOP **core tables** and RAM usage"
            Tables `CONCEPT` and `PERSON` are always loaded in RAM.

            `VISIT_OCCURRENCE` will also be loaded if present, and this can **consume a lot of RAM** depending on its size. You might simply skip this table when exporting OMOP CDM data, as its information is only used as additional property `_visit`, but it is not part of the Beacon v2 or Phenopackets schema.
            
        #### Selected table(s)

        You can narrow down the selection to a set of table(s).

        ??? Warning "About tables `CONCEPT` and `PERSON`"
            Tables `CONCEPT` and `PERSON` are always loaded as they're needed for the conversion. You don't need to specify them.

        ```
        convert-pheno -iomop omop_dump.sql.gz -obff individuals_measurement.json.gz --omop-tables DRUG_EXPOSURE --stream
        ```

        Running multiple jobs in `--stream` mode will create a bunch of `JSON` files instead of one. It's OK, as the files we're creating are **intermediate** files.

        ??? Danger "_Pros_ and _Cons_ of incremental data load (`--stream` mode)"
            Incremental data load facilitates the processing of huge files. The only substantive difference compared to the `--no-stream` mode is that the data will not be consolidated at the patient or individual level, which is merely a **cosmetic concern**. Ultimately, the data will be loaded into a **database**, such as _MongoDB_, where the linking of data through keys can be managed. In most cases, the implementation of a pre-built API, such as the one described in the [B2RI documentation](https://b2ri-documentation.readthedocs.io/en/latest), will be added to further enhance the functionality.

            Number of rows | Estimated RAM memory | Estimated time
                   :---:   |   :---:              | :---:
                    100K   | 500MB                | 7s
                    500K   | 500MB                | 18s
                    1M     | 500MB                | 35s
                    2M     | 500MB                | 1m5s

            1 x Intel(R) Xeon(R) W-1350P @ 4.00GHz - 32GB RAM - SSD

            Note that the output JSON files generated in `--stream` mode will always include information from the `PERSON` and `CONCEPT` tables. Therefore, **both tables must be loaded into RAM** (along with `VISIT_OCCURRENCE` if present). **The size of these tables will obviously impact RAM usage**. Although having this information is not a mandatory requirement for _MongoDB_, it helps in validating the data against Beacon v2 JSON schemas. According to JSON Schema terminology, these files contain `required` properties for [BFF](bff.md) and [PXF](pxf.md). For more details on validation, refer to the [BFF Validator](https://github.com/EGA-archive/beacon2-ri-tools/tree/main/utils/bff_validator).

        ??? Tip "About parallelization and speed"
            `Convert-Pheno` has been optimized for speed, and, in general the CLI results are generated almost immediatly. For instance, all tests with synthetic data take less than a second or a few seconds to complete. It should be noted that the speed of the results depends on the performance of the CPU and disk speed. When `Convert-Pheno` has to retrieve ontologies from a database to annotate the data, the processing takes longer.

            The calculation is I/O limited and using _internal_ [threads](https://en.wikipedia.org/wiki/Thread_(computing)) did not speed up the calculation. Another valid option is to run **simultaneous jobs** with external tools such as [GNU Parallel](https://www.gnu.org/software/parallel), but keep in mind that **SQLite** database _may_ complain.

            As a final consideration, it is important to remember that pheno-clinical data conversions are executed only "once". The goal is obtaining **intermediate files** which will be later loaded into a database. If a large file has been converted, it is verly likely that the **performance bottleneck** will not occur at the `Convert-Pheno` step, but rather during the **database load**.

=== "Module"

    For developers who wish to retrieve data in **real time**, the module can also receive OMOP tables directly as in-memory data structures. The module interface uses one flat payload. Unlike the API, the arguments are not split into `input`, `output`, and `options` sections.

    !!! Tip "Tip"
        Definitions are stored in table `CONCEPT`. If you do not pass the relevant `CONCEPT` rows yourself, set `ohdsi_db => 1` (or `True` in Python) so the converter can resolve terms from the Athena-OHDSI SQLite database.

    === "Perl"
        ```perl
        use Convert::Pheno;

        my $payload = {
            method   => 'omop2bff',
            ohdsi_db => 0,
            test     => 1,
            data     => {
                PERSON => [
                    {
                        person_id                => 974,
                        gender_concept_id        => 8532,
                        gender_source_value      => 'F',
                        year_of_birth            => 1963,
                        ethnicity_source_value   => 'west_indian',
                    }
                ],
                CONCEPT => [
                    {
                        concept_id     => 8532,
                        concept_name   => 'FEMALE',
                        vocabulary_id  => 'Gender',
                    }
                ],
            },
        };

        my $convert = Convert::Pheno->new($payload);
        my $bff     = $convert->omop2bff;
        ```

    === "Python"

        ```python
        from convertpheno import PythonBinding

        payload = {
            "method": "omop2bff",
            "ohdsi_db": False,
            "test": 1,
            "data": {
                "PERSON": [
                    {
                        "person_id": 974,
                        "gender_concept_id": 8532,
                        "gender_source_value": "F",
                        "year_of_birth": 1963,
                        "ethnicity_source_value": "west_indian",
                    }
                ],
                "CONCEPT": [
                    {
                        "concept_id": 8532,
                        "concept_name": "FEMALE",
                        "vocabulary_id": "Gender",
                    }
                ],
            },
        }

        bff = PythonBinding(payload).convert_pheno()
        ```

=== "API"

    All said for the Module also works for the API.
    The API request payload now uses explicit `conversion`, `input`, `output`, and `options` sections. A small example is:

    ```json
    {
      "conversion": "omop2bff",
      "input": {
        "data": {
          "PERSON": [
            {
              "person_id": 974,
              "gender_concept_id": 8532,
              "year_of_birth": 1963
            }
          ],
          "CONCEPT": [
            {
              "concept_id": 8532,
              "concept_name": "FEMALE",
              "vocabulary_id": "Gender"
            }
          ]
        }
      },
      "output": {
        "entities": ["individuals"]
      },
      "options": {
        "ohdsi_db": true
      }
    }
    ```

    See a larger example payload [here](https://github.com/cnag-biomedical-informatics/convert-pheno/blob/main/api/perl/omop.json).
