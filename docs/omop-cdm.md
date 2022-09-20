# OMOP - CDM

**OMOP-CDM** stands for **O**bservational **M**edical **O**utcomes **P**artnership **C**ommon **D**ata **M**odel.

**OMOP-CDM** [documentation](https://www.ohdsi.org/data-standardization/the-common-data-model).


## OMOP as input

### Command-line

If you're using a OMOP-CDM export (`csv`) or dump (`sql`) file with the `convert-pheno` command-line interface just provide the right [syntax](https://github.com/mrueda/Convert-Pheno#synopsis):


```
convert-pheno -iomop omop_dump.sql -obff individuals.json
```

### Module

Usually, OMOP-CDM databases are implemented as PostgreSQL instances. Programatically, we let the developer deal with database credentials, queries, etc. which we assume are performed with one of the many available [drivers for PostgreSQL](https://wiki.postgresql.org/wiki/List_of_drivers).

The idea is that we will pass the essential information as a hash (Perl) or dictionary (Python). You don't need to send all the tables shown in the example below, just the ones you want to transform.

__NB__: The defintions are stored in table `CONCEPT`. If you send the complete `CONCEPT` table then `Convert::Pheno` will be able to find a match, otherwise it will require setting the parameter `ohdsi_db = 1` (true).

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

### API

See example data [here](json/omop-cdm.json).

```JSON
{
"data": { ... },
"method": "omop2bff",
"ohdsi_db": true
}
```
