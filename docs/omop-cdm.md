**OMOP-CDM** stands for **O**bservational **M**edical **O**utcomes **P**artnership **C**ommon **D**ata **M**odel. **OMOP-CDM** [documentation](https://www.ohdsi.org/data-standardization/the-common-data-model).

<figure markdown>
   ![OMOP-CDM](https://www.ohdsi.org/wp-content/uploads/2015/02/h243-ohdsi-logo-with-text.png){ width="400" }
   <figcaption>Image extracted from www.ohdsi.org</figcaption>
</figure>

OMOP-CDM databases are typically implemented as PostgreSQL instances. Based on our experience, OMOP users will often export their databases periodically in either `.sql` or `.csv` format.

## OMOP as input

!!! Hint "OMOP-CDM supported version(s)"
         We currently support **v5.4**. We have everything ready for supporting v6 once we are able to test the code with v6 projects.


=== "Command-line"

    When using the `convert-pheno` command-line interface, simply ensure the [correct syntax](https://github.com/mrueda/convert-pheno#synopsis) is provided.

    === "Small to medium-sized files (<1GB)"

        Usage:

        ```
        convert-pheno -iomop omop_dump.sql -obff individuals.json
        ```

        It is possible to convert specific tables. For instance, in case you only want to convert `MEASUREMENT` table use the option `--omop-tables`. The option accepts a list of tables (case insensitive) separated by spaces:


        !!! Warning "About tables `CONCEPT` and `PERSON`"
            Tables `CONCEPT` and `PERSON` are always loaded as they're needed for the conversion. You don't need to specify them.

        ```
        convert-pheno -iomop omop_dump.sql -obff individuals.json --omop-tables MEASUREMENT
        ```

        In some cases, your `CONCEPT` table may not contain all posible standard concepts. In this case, you can use the flag `--ohdsi-db` that will check an internal database whenever the `concept_id` can not be found inside your `CONCEPT` table.

        ```
        convert-pheno -iomop omop_dump.sql -obff individuals_measurement.json --omop-tables MEASUREMENT --ohdsi-db
        ```

        !!! Danger "RAM memory usage when merging rows by atribute `person_id`"
            When working with `-iomop` and `--no-stream` (default), `Convert-Pheno` will consolidate all the values corresponding to a given `person_id` under the same object. In order to do this, we need to store all data in the **RAM** memory. The reason for storing the data in RAM is because the rows are **not adjacent** (they are not pre-sorted by `person_id`) and can originate from **distinct tables**.

            If your computer only has 4GB-8GB of RAM and you plan to convert **large files** we recommend you to use the flag `--stream` which will process your tables **incrementally** (i.e.,line-by-line), instead of loading them into memory. 

        
    === "Large files (>1GB)"


        #### CSV

        We recommend running one table at a time in **parallel**. If you exceed the amount of RAM, try splitting your CSV tables in chunks.

        ```
        convert-pheno -iomop omop_dump.sql -obff individuals.json --omop-tables MEASUREMENT
        ```


        #### SQL exports

        For large SQL exports, `Convert-Pheno` takes a different approach. The files will be parsed incrementally incrementally and serialize it (print it) line-by-line.

        To choose incremental data processing we'll be using the flag `--stream`:

        ```
        convert-pheno -iomop omop_dump.sql -obff individuals.json --stream
        ```

        You can narrow down the selection to a given table(s). This will come in handy to run jobs in **parallel**.

        !!! Warning "About tables `CONCEPT` and `PERSON`"
            Tables `CONCEPT` and `PERSON` are always loaded as they're needed for the conversion. You don't need to specify them.

        ```
        convert-pheno -iomop omop_dump.sql -obff individuals_measurement.json --omop-tables MEASUREMENT --stream
        ```

        This way you will end-up with a bunch of `JSON` files instead of one. It's OK, as the files we're creating are **intermediate** files.

        !!! Danger "_Pros_ and _Cons_ of incremental data load"
            Incremental data load facilitates the processing of huge files. The only substantive difference compared to the `--no-stream` mode is that the data will not be consolidated at the patient or individual level, which is merely a **cosmetic concern**. Ultimately, the data will be loaded into a **database**, such as _MongoDB_, where the linking of data through keys can be managed. In most cases, the implementation of a pre-built API, such as the one described in the [B2RI documentation](https://b2ri-documentation.readthedocs.io/en/latest), will be added to further enhance the functionality.

            Note that the output JSON files generated in `--stream` mode will always include information from both the `PERSON` and `CONCEPT` tables. This is not a mandatory requirement, but it serves to facilitate subsequent [validation of the data against JSON schemas](https://github.com/EGA-archive/beacon2-ri-tools/tree/main/utils/bff_validator). In terms of the JSON Schema terminology, these files contain `required` properties for [BFF](bff.md) and [PXF](pxf.md).

        !!! Tip "About Parallelization"
            `Convert-Pheno` has been optimized for speed, and, in general the CLI results are generated almost immediatly. For instance, all tests with synthetic data take less than a second of a few seconds to complete. It should be noted that the speed of the results depends on the performance of the CPU and disk speed. If `Convert-Pheno` must retrieve ontologies from a database to annotate the data, the process may take longer.

            The calculation is I/O limited and using internal [threads](https://en.wikipedia.org/wiki/Thread_(computing)) does not really speed up the calculation much. In any case, you can try running simultaneous jobs with external tools such as [GNU Parallel](https://www.gnu.org/software/parallel).

            As a final consideration, it is important to recall that pheno-clinical data conversions are executed only "once" and create **intermediate files**. If a large file has been converted, it is likely that the **performance bottleneck** will not occur within the `Convert-Pheno` software, but rather during the **ingestion phase in the database**.

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
          ohdsi_db => 1,
          data => 
                 {
                  'CONCEPT' => [
                                 {
                                   'concept_class_id' => '4-char billing code',
                                   'concept_code' => 'K92.2',
                                   'concept_id' => '35208414',
                                   'concept_name' => 'Gastrointestinal hemorrhage, unspecified',
                                   'domain_id' => 'Condition',
                                   'invalid_reason' => undef,
                                   'standard_concept' => '',
                                   'valid_end_date' => '2099-12-31',
                                   'valid_start_date' => '2007-01-01',
                                   'vocabulary_id' => 'ICD10CM'
                                 },
                                 {...}
                               ],
                  'CONDITION_ERA' => [
                                       {
                                         'condition_concept_id' => '40481087',
                                         'condition_era_end_date' => '2015-10-19',
                                         'condition_era_id' => '60911',
                                         'condition_era_start_date' => '2015-10-12',
                                         'condition_occurrence_count' => '1',
                                         'person_id' => '3609'
                                       }
                                     ],
                  'CONDITION_OCCURRENCE' => [
                                              {
                                                'condition_concept_id' => '4112343',
                                                'condition_end_date' => '2015-10-14',
                                                'condition_end_datetime' => '2015-10-14 00:00:00',
                                                'condition_occurrence_id' => '4483',
                                                'condition_source_concept_id' => '4112343',
                                                'condition_source_value' => '195662009',
                                                'condition_start_date' => '2015-10-02',
                                                'condition_start_datetime' => '2015-10-02 00:00:00',
                                                'condition_status_concept_id' => '0',
                                                'condition_status_source_value' => '',
                                                'condition_type_concept_id' => '32020',
                                                'person_id' => '263',
                                                'provider_id' => '\\N',
                                                'stop_reason' => '',
                                                'visit_detail_id' => '0',
                                                'visit_occurrence_id' => '17479'
                                              }
                                            ],
                              ],
                  'DRUG_ERA' => [
                                  {
                                    'drug_concept_id' => '738818',
                                    'drug_era_end_date' => '1984-10-03',
                                    'drug_era_id' => '2707',
                                    'drug_era_start_date' => '1984-09-19',
                                    'drug_exposure_count' => '1',
                                    'gap_days' => '5389',
                                    'person_id' => '181'
                                  }
                                ],
                  'DRUG_EXPOSURE' => [
                                       {
                                         'days_supply' => '0',
                                         'dose_unit_source_value' => undef,
                                         'drug_concept_id' => '40213160',
                                         'drug_exposure_end_date' => '1960-04-09',
                                         'drug_exposure_end_datetime' => '1960-04-09 00:00:00',
                                         'drug_exposure_id' => '26318',
                                         'drug_exposure_start_date' => '1960-04-09',
                                         'drug_exposure_start_datetime' => '1960-04-09 00:00:00',
                                         'drug_source_concept_id' => '40213160',
                                         'drug_source_value' => '10',
                                         'drug_type_concept_id' => '581452',
                                         'lot_number' => '0',
                                         'person_id' => '573',
                                         'provider_id' => '0',
                                         'quantity' => '0',
                                         'refills' => '0',
                                         'route_concept_id' => '0',
                                         'route_source_value' => undef,
                                         'sig' => '',
                                         'stop_reason' => '',
                                         'verbatim_end_date' => '1960-04-09',
                                         'visit_detail_id' => '0',
                                         'visit_occurrence_id' => '38004'
                                       }
                                     ],
                  'MEASUREMENT' => [
                                     {
                                       'measurement_concept_id' => '3006322',
                                       'measurement_date' => '1998-10-03',
                                       'measurement_datetime' => '1998-10-03 00:00:00',
                                       'measurement_id' => '10204',
                                       'measurement_source_concept_id' => '3006322',
                                       'measurement_source_value' => '8331-1',
                                       'measurement_time' => '1998-10-03',
                                       'measurement_type_concept_id' => '5001',
                                       'operator_concept_id' => '0',
                                       'person_id' => '974',
                                       'provider_id' => '0',
                                       'range_high' => '\\N',
                                       'range_low' => '\\N',
                                       'unit_concept_id' => '0',
                                       'unit_source_value' => undef,
                                       'value_as_concept_id' => '0',
                                       'value_as_number' => '\\N',
                                       'value_source_value' => undef,
                                       'visit_detail_id' => '0',
                                       'visit_occurrence_id' => '64994'
                                     }
                                   ],
                  'OBSERVATION' => [
                                     {
                                       'observation_concept_id' => '4323208',
                                       'observation_date' => '1960-06-07',
                                       'observation_datetime' => '1960-06-07 00:00:00',
                                       'observation_id' => '25197',
                                       'observation_source_concept_id' => '4323208',
                                       'observation_source_value' => '428251008',
                                       'observation_type_concept_id' => '38000276',
                                       'person_id' => '1504',
                                       'provider_id' => '0',
                                       'qualifier_concept_id' => '0',
                                       'qualifier_source_value' => undef,
                                       'unit_concept_id' => '0',
                                       'unit_source_value' => undef,
                                       'value_as_concept_id' => '0',
                                       'value_as_number' => '\\N',
                                       'value_as_string' => '',
                                       'visit_detail_id' => '0',
                                       'visit_occurrence_id' => '100221'
                                     }
                                   ],
                  'OBSERVATION_PERIOD' => [
                                            {
                                              'observation_period_end_date' => '2007-02-06',
                                              'observation_period_id' => '6',
                                              'observation_period_start_date' => '1963-12-31',
                                              'period_type_concept_id' => '44814724',
                                              'person_id' => '6'
                                            }
                                          ],
                  'PERSON' => [
                                {
                                  'birth_datetime' => '1963-12-31 00:00:00',
                                  'care_site_id' => '\\N',
                                  'day_of_birth' => '31',
                                  'ethnicity_concept_id' => '0',
                                  'ethnicity_source_concept_id' => '0',
                                  'ethnicity_source_value' => 'west_indian',
                                  'gender_concept_id' => '8532',
                                  'gender_source_concept_id' => '0',
                                  'gender_source_value' => 'F',
                                  'location_id' => '\\N',
                                  'month_of_birth' => '12',
                                  'person_id' => '6',
                                  'person_source_value' => '001f4a87-70d0-435c-a4b9-1425f6928d33',
                                  'provider_id' => '\\N',
                                  'race_concept_id' => '8516',
                                  'race_source_concept_id' => '0',
                                  'race_source_value' => 'black',
                                  'year_of_birth' => '1963'
                                }
                              ],
                  'PROCEDURE_OCCURRENCE' => [
                                              {
                                                'modifier_concept_id' => '0',
                                                'modifier_source_value' => undef,
                                                'person_id' => '343',
                                                'procedure_concept_id' => '4107731',
                                                'procedure_date' => '1992-02-01',
                                                'procedure_datetime' => '1992-02-01 00:00:00',
                                                'procedure_occurrence_id' => '3554',
                                                'procedure_source_concept_id' => '4107731',
                                                'procedure_source_value' => '180256009',
                                                'procedure_type_concept_id' => '38000275',
                                                'provider_id' => '\\N',
                                                'quantity' => '\\N',
                                                'visit_detail_id' => '0',
                                                'visit_occurrence_id' => '22951'
                                              }
                                            ],
                  'RELATIONSHIP' => [
                                      {
                                        'defines_ancestry' => '0',
                                        'is_hierarchical' => '0',
                                        'relationship_concept_id' => '44818895',
                                        'relationship_id' => 'Acc device used by',
                                        'relationship_name' => 'Access device used by (SNOMED)',
                                        'reverse_relationship_id' => 'Using acc device'
                                      }
                                    ],
                  'VISIT_OCCURRENCE' => [
                                          {
                                            'admitting_source_concept_id' => '0',
                                            'admitting_source_value' => '',
                                            'care_site_id' => '\\N',
                                            'discharge_to_concept_id' => '0',
                                            'discharge_to_source_value' => '',
                                            'person_id' => '986',
                                            'preceding_visit_occurrence_id' => '65444',
                                            'provider_id' => '\\N',
                                            'visit_concept_id' => '9201',
                                            'visit_end_date' => '1996-08-22',
                                            'visit_end_datetime' => '1996-08-22 00:00:00',
                                            'visit_occurrence_id' => '65475',
                                            'visit_source_concept_id' => '0',
                                            'visit_source_value' => 'b2a6f7d3-bed4-4e23-aaf3-74bc5ad2d0c6',
                                            'visit_start_date' => '1996-08-21',
                                            'visit_start_datetime' => '1996-08-21 00:00:00',
                                            'visit_type_concept_id' => '44818517'
                                          }
                                        ],
                  'VOCABULARY' => [
                                    {
                                      'vocabulary_concept_id' => '45756746',
                                      'vocabulary_id' => 'ABMS',
                                      'vocabulary_name' => 'Provider Specialty (American Board of Medical Specialties)',
                                      'vocabulary_reference' => 'http://www.abms.org/member-boards/specialty-subspecialty-certificates',
                                      'vocabulary_version' => '2018-06-26 ABMS'
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
           "ohdsi_db": True,
           "data": {
             "CDM_SOURCE": [
               {
                 "cdm_etl_reference": "https://github.com/OHDSI/ETL-Synthea",
                 "cdm_holder": "OHDSI Community",
                 "cdm_release_date": "2019-05-25",
                 "cdm_source_abbreviation": "Synthea",
                 "cdm_source_name": "Synthea synthetic health database",
                 "cdm_version": "v5.3.1",
                 "source_description": "SyntheaTM is a Synthetic Patient Population Simulator. The goal is to output synthetic, realistic (but not real), patient data and associated health records in a variety of formats.",
                 "source_documentation_reference": "https://synthetichealth.github.io/synthea/",
                 "source_release_date": "2019-05-25",
                 "vocabulary_version": "v5.0 18-JAN-19"
               }
             ],
             "CONCEPT": [
               {
                 "concept_class_id": "4-char billing code",
                 "concept_code": "K92.2",
                 "concept_id": 35208414,
                 "concept_name": "Gastrointestinal hemorrhage, unspecified",
                 "domain_id": "Condition",
                 "invalid_reason": null,
                 "standard_concept": "",
                 "valid_end_date": "2099-12-31",
                 "valid_start_date": "2007-01-01",
                 "vocabulary_id": "ICD10CM"
               }
             ],
             "CONCEPT_ANCESTOR": [
               {
                 "ancestor_concept_id": 4180628,
                 "descendant_concept_id": 313217,
                 "max_levels_of_separation": 6,
                 "min_levels_of_separation": 5
               }
             ],
             "CONCEPT_RELATIONSHIP": [
               {
                 "concept_id_1": 192671,
                 "concept_id_2": 35208414,
                 "invalid_reason": null,
                 "relationship_id": "Mapped from",
                 "valid_end_date": "2099-12-31",
                 "valid_start_date": "1970-01-01"
               }
             ],
             "CONCEPT_SYNONYM": [
               {
                 "concept_id": 964261,
                 "concept_synonym_name": "cyanocobalamin 5000 MCG/ML Injectable Solution",
                 "language_concept_id": 4180186
               }
             ],
             "CONDITION_ERA": [
               {
                 "condition_concept_id": 40481087,
                 "condition_era_end_date": "2015-10-19",
                 "condition_era_id": 60911,
                 "condition_era_start_date": "2015-10-12",
                 "condition_occurrence_count": 1,
                 "person_id": 3609
               }
             ],
             "CONDITION_OCCURRENCE": [
               {
                 "condition_concept_id": 4112343,
                 "condition_end_date": "2015-10-14",
                 "condition_end_datetime": "2015-10-14 00:00:00",
                 "condition_occurrence_id": 4483,
                 "condition_source_concept_id": 4112343,
                 "condition_source_value": 195662009,
                 "condition_start_date": "2015-10-02",
                 "condition_start_datetime": "2015-10-02 00:00:00",
                 "condition_status_concept_id": 0,
                 "condition_status_source_value": "",
                 "condition_type_concept_id": 32020,
                 "person_id": 263,
                 "provider_id": "\\N",
                 "stop_reason": "",
                 "visit_detail_id": 0,
                 "visit_occurrence_id": 17479
               }
             ],
             "DOMAIN": [
               {
                 "domain_concept_id": 19,
                 "domain_id": "Condition",
                 "domain_name": "Condition"
               }
             ],
             "DRUG_ERA": [
               {
                 "drug_concept_id": 738818,
                 "drug_era_end_date": "1984-10-03",
                 "drug_era_id": 2707,
                 "drug_era_start_date": "1984-09-19",
                 "drug_exposure_count": 1,
                 "gap_days": 5389,
                 "person_id": 181
               }
             ],
             "DRUG_EXPOSURE": [
               {
                 "days_supply": 0,
                 "dose_unit_source_value": null,
                 "drug_concept_id": 40213160,
                 "drug_exposure_end_date": "1960-04-09",
                 "drug_exposure_end_datetime": "1960-04-09 00:00:00",
                 "drug_exposure_id": 26318,
                 "drug_exposure_start_date": "1960-04-09",
                 "drug_exposure_start_datetime": "1960-04-09 00:00:00",
                 "drug_source_concept_id": 40213160,
                 "drug_source_value": 10,
                 "drug_type_concept_id": 581452,
                 "lot_number": 0,
                 "person_id": 573,
                 "provider_id": 0,
                 "quantity": 0,
                 "refills": 0,
                 "route_concept_id": 0,
                 "route_source_value": null,
                 "sig": "",
                 "stop_reason": "",
                 "verbatim_end_date": "1960-04-09",
                 "visit_detail_id": 0,
                 "visit_occurrence_id": 38004
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
                 "value_as_number": "\\N",
                 "value_source_value": null,
                 "visit_detail_id": 0,
                 "visit_occurrence_id": 64994
               }
             ],
             "OBSERVATION": [
               {
                 "observation_concept_id": 4323208,
                 "observation_date": "1960-06-07",
                 "observation_datetime": "1960-06-07 00:00:00",
                 "observation_id": 25197,
                 "observation_source_concept_id": 4323208,
                 "observation_source_value": 428251008,
                 "observation_type_concept_id": 38000276,
                 "person_id": 1504,
                 "provider_id": 0,
                 "qualifier_concept_id": 0,
                 "qualifier_source_value": null,
                 "unit_concept_id": 0,
                 "unit_source_value": null,
                 "value_as_concept_id": 0,
                 "value_as_number": "\\N",
                 "value_as_string": "",
                 "visit_detail_id": 0,
                 "visit_occurrence_id": 100221
               }
             ],
             "OBSERVATION_PERIOD": [
               {
                 "observation_period_end_date": "2007-02-06",
                 "observation_period_id": 6,
                 "observation_period_start_date": "1963-12-31",
                 "period_type_concept_id": 44814724,
                 "person_id": 6
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
                 "person_id": 6,
                 "person_source_value": "001f4a87-70d0-435c-a4b9-1425f6928d33",
                 "provider_id": "\\N",
                 "race_concept_id": 8516,
                 "race_source_concept_id": 0,
                 "race_source_value": "black",
                 "year_of_birth": 1963
               }
             ],
             "PROCEDURE_OCCURRENCE": [
               {
                 "modifier_concept_id": 0,
                 "modifier_source_value": null,
                 "person_id": 343,
                 "procedure_concept_id": 4107731,
                 "procedure_date": "1992-02-01",
                 "procedure_datetime": "1992-02-01 00:00:00",
                 "procedure_occurrence_id": 3554,
                 "procedure_source_concept_id": 4107731,
                 "procedure_source_value": 180256009,
                 "procedure_type_concept_id": 38000275,
                 "provider_id": "\\N",
                 "quantity": "\\N",
                 "visit_detail_id": 0,
                 "visit_occurrence_id": 22951
               }
             ],
             "RELATIONSHIP": [
               {
                 "defines_ancestry": 0,
                 "is_hierarchical": 0,
                 "relationship_concept_id": 44818895,
                 "relationship_id": "Acc device used by",
                 "relationship_name": "Access device used by (SNOMED)",
                 "reverse_relationship_id": "Using acc device"
               }
             ],
             "VISIT_OCCURRENCE": [
               {
                 "admitting_source_concept_id": 0,
                 "admitting_source_value": "",
                 "care_site_id": "\\N",
                 "discharge_to_concept_id": 0,
                 "discharge_to_source_value": "",
                 "person_id": 986,
                 "preceding_visit_occurrence_id": 65444,
                 "provider_id": "\\N",
                 "visit_concept_id": 9201,
                 "visit_end_date": "1996-08-22",
                 "visit_end_datetime": "1996-08-22 00:00:00",
                 "visit_occurrence_id": 65475,
                 "visit_source_concept_id": 0,
                 "visit_source_value": "b2a6f7d3-bed4-4e23-aaf3-74bc5ad2d0c6",
                 "visit_start_date": "1996-08-21",
                 "visit_start_datetime": "1996-08-21 00:00:00",
                 "visit_type_concept_id": 44818517
               }
             ],
             "VOCABULARY": [
               {
                 "vocabulary_concept_id": 45756746,
                 "vocabulary_id": "ABMS",
                 "vocabulary_name": "Provider Specialty (American Board of Medical Specialties)",
                 "vocabulary_reference": "http://www.abms.org/member-boards/specialty-subspecialty-certificates",
                 "vocabulary_version": "2018-06-26 ABMS"
               }
             ]
           }
         }
         ```

=== "API"

    All said for the Module also works for the API.
    See example data [here](json/omop-cdm.json).

    ```json
    {
      "data": { ... },
      "method": "omop2bff",
      "ohdsi_db": true
    }
    ```

