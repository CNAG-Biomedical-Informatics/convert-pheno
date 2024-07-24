**OMOP CDM** stands for **O**bservational **M**edical **O**utcomes **P**artnership **C**ommon **D**ata **M**odel. **OMOP CDM** [documentation](https://www.ohdsi.org/data-standardization/the-common-data-model).

<figure markdown>
   ![OMOP CDM](https://www.ohdsi.org/wp-content/uploads/2015/02/h243-ohdsi-logo-with-text.png){ width="400" }
   <figcaption>Image extracted from www.ohdsi.org</figcaption>
</figure>

The **OMOP CDM** is designed to be database-agnostic, which means it can be implemented using different relational database management systems, with **PostgreSQL** being a popular choice.

`Convert-Pheno` is capable of performing both **file-based conversions** (from PostgreSQL exports in `.sql` or from any other SQL database via `.csv` files) and **real-time conversions** (e.g., from [SQL queries](http://cdmqueries.omop.org)) as long as the data has been converted to the accepted JSON format.

??? Warning "About OMOP CDM longitudinal data"
    OMOP CDM stores `visit_occurrence_id` for each `person_id` in the `VISIT_OCCURRENCE table`. However, [Beacon v2 Models](https://docs.genomebeacons.org/schemas-md/individuals_defaultSchema) currently lack a way to store longitudinal data. To address this, we added a property named `_visit` to each record, which stores visit information. This property will be serialized only if the `VISIT_OCCURRENCE` table is provided.

!!! Tip "OMOP CDM supported version(s)"
    Currently, Convert-Pheno supports versions **5.3** and **5.4** of OMOP CDM, and its prepared to support v6 once we can test the code with v6 projects.

## OMOP as input

=== "Command-line"

    When using the `convert-pheno` command-line interface, simply ensure the [correct syntax](usage.md) is provided.

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
            We only support output to BFF (`-obff`).

        #### All tables at once

        ```
        convert-pheno -iomop omop_dump.sql.gz -obff individuals.json.gz --stream
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

    For developers who wish to retrieve data in **real-time**, we also offer the option of using the module version. With this option, the developer has to handle database credentials, queries, etc. using one of the many available PostgreSQL [drivers](https://wiki.postgresql.org/wiki/List_of_drivers).

    The idea is to pass the essential information to `Convert-Pheno` as a hash (in Perl) or dictionary (in Python). It is not necessary to send all the tables shown in the example, only the ones you wish to transform.


    !!! Tip "Tip"
        The defintions are stored in table `CONCEPT`. If you send the complete `CONCEPT` table then `Convert-Pheno` will be able to find a match, otherwise it will require setting the parameter `ohdsi_db = 1` (true).

    === "Perl"
        ```Perl
        my $data = 
        {
          method => 'omop2bff',
          ohdsi_db => 0,
          data => 
          {
              'CONCEPT' => [
                             {
                               'concept_class_id' => 'Undefined',
                               'concept_code' => 'No matching concept',
                               'concept_id' => 0,
                               'concept_name' => 'No matching concept',
                               'domain_id' => 'Metadata',
                               'invalid_reason' => undef,
                               'standard_concept' => undef,
                               'valid_end_date' => '2099-12-31',
                               'valid_start_date' => '1970-01-01',
                               'vocabulary_id' => 'None'
                             },
                             {
                               'concept_class_id' => 'Gender',
                               'concept_code' => 'F',
                               'concept_id' => 8532,
                               'concept_name' => 'FEMALE',
                               'domain_id' => 'Gender',
                               'invalid_reason' => undef,
                               'standard_concept' => 'S',
                               'valid_end_date' => '2099-12-31',
                               'valid_start_date' => '1970-01-01',
                               'vocabulary_id' => 'Gender'
                             },
                             {
                               'concept_class_id' => 'Clinical Observation',
                               'concept_code' => '8331-1',
                               'concept_id' => 3006322,
                               'concept_name' => 'Oral temperature',
                               'domain_id' => 'Measurement',
                               'invalid_reason' => undef,
                               'standard_concept' => 'S',
                               'valid_end_date' => '2099-12-31',
                               'valid_start_date' => '1996-09-06',
                               'vocabulary_id' => 'LOINC'
                             }
                           ],
              'MEASUREMENT' => [
                                 {
                                   'measurement_concept_id' => 3006322,
                                   'measurement_date' => '1998-10-03',
                                   'measurement_datetime' => '1998-10-03 00:00:00',
                                   'measurement_id' => 10204,
                                   'measurement_source_concept_id' => 3006322,
                                   'measurement_source_value' => '8331-1',
                                   'measurement_time' => '1998-10-03',
                                   'measurement_type_concept_id' => 5001,
                                   'operator_concept_id' => 0,
                                   'person_id' => 974,
                                   'provider_id' => 0,
                                   'range_high' => '\\N',
                                   'range_low' => '\\N',
                                   'unit_concept_id' => 0,
                                   'unit_source_value' => undef,
                                   'value_as_concept_id' => 0,
                                   'value_as_number' => 4,
                                   'value_source_value' => undef,
                                   'visit_detail_id' => 0,
                                   'visit_occurrence_id' => 64994
                                 }
                               ],
              'PERSON' => [
                            {
                              'birth_datetime' => '1963-12-31 00:00:00',
                              'care_site_id' => '\\N',
                              'day_of_birth' => 31,
                              'ethnicity_concept_id' => 0,
                              'ethnicity_source_concept_id' => 0,
                              'ethnicity_source_value' => 'west_indian',
                              'gender_concept_id' => 8532,
                              'gender_source_concept_id' => 0,
                              'gender_source_value' => 'F',
                              'location_id' => '\\N',
                              'month_of_birth' => 12,
                              'person_id' => 974,
                              'person_source_value' => '001f4a87-70d0-435c-a4b9-1425f6928d33',
                              'provider_id' => '\\N',
                              'race_concept_id' => 8516,
                              'race_source_concept_id' => 0,
                              'race_source_value' => 'black',
                              'year_of_birth' => 1963
                            }
                          ]
               }
        };
        ```

    === "Python"

         ```Python
         data = 
         {
           "method": "omop2bff",
           "ohdsi_db": False,
           "data": {
             "CONCEPT": [
               {
                 "concept_class_id": "Undefined",
                 "concept_code": "No matching concept",
                 "concept_id": 0,
                 "concept_name": "No matching concept",
                 "domain_id": "Metadata",
                 "invalid_reason": null,
                 "standard_concept": null,
                 "valid_end_date": "2099-12-31",
                 "valid_start_date": "1970-01-01",
                 "vocabulary_id": "None"
               },
               {
                 "concept_class_id": "Gender",
                 "concept_code": "F",
                 "concept_id": 8532,
                 "concept_name": "FEMALE",
                 "domain_id": "Gender",
                 "invalid_reason": null,
                 "standard_concept": "S",
                 "valid_end_date": "2099-12-31",
                 "valid_start_date": "1970-01-01",
                 "vocabulary_id": "Gender"
               },
               {
                 "concept_class_id": "Clinical Observation",
                 "concept_code": "8331-1",
                 "concept_id": 3006322,
                 "concept_name": "Oral temperature",
                 "domain_id": "Measurement",
                 "invalid_reason": null,
                 "standard_concept": "S",
                 "valid_end_date": "2099-12-31",
                 "valid_start_date": "1996-09-06",
                 "vocabulary_id": "LOINC"
               }
             ],
             "MEASUREMENT": [
               {
                 "measurement_concept_id": 3006322,
                 "measurement_date": "1998-10-03",
                 "measurement_datetime": "1998-10-03 00:00:00",
                 "measurement_id": 10204,
                 "measurement_source_concept_id": 3006322,
                 "measurement_source_value": "8331-1",
                 "measurement_time": "1998-10-03",
                 "measurement_type_concept_id": 5001,
                 "operator_concept_id": 0,
                 "person_id": 974,
                 "provider_id": 0,
                 "range_high": "\\N",
                 "range_low": "\\N",
                 "unit_concept_id": 0,
                 "unit_source_value": null,
                 "value_as_concept_id": 0,
                 "value_as_number": 4,
                 "value_source_value": null,
                 "visit_detail_id": 0,
                 "visit_occurrence_id": 64994
               }
             ],
             "PERSON": [
               {
                 "birth_datetime": "1963-12-31 00:00:00",
                 "care_site_id": "\\N",
                 "day_of_birth": 31,
                 "ethnicity_concept_id": 0,
                 "ethnicity_source_concept_id": 0,
                 "ethnicity_source_value": "west_indian",
                 "gender_concept_id": 8532,
                 "gender_source_concept_id": 0,
                 "gender_source_value": "F",
                 "location_id": "\\N",
                 "month_of_birth": 12,
                 "person_id": 974,
                 "person_source_value": "001f4a87-70d0-435c-a4b9-1425f6928d33",
                 "provider_id": "\\N",
                 "race_concept_id": 8516,
                 "race_source_concept_id": 0,
                 "race_source_value": "black",
                 "year_of_birth": 1963
               }
             ]
           }
         }
         ```

=== "API"

    All said for the Module also works for the API.
    See example data [here](https://github.com/cnag-biomedical-informatics/convert-pheno/blob/main/api/perl/omop.json).

    ```json
    {
      "data": { ... },
      "method": "omop2bff",
      "ohdsi_db": true
    }
    ```

