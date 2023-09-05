# Terms

## diseases
|  OMOP Table(s)                                              | OMOP Variable                                              | BFF JSON path                                               |
|  :---:                                                      | :---:                                                      | :---:                                                       |
|  CONDITION_OCCURRENCE, PERSON                               | condition_start_date, birth_datetime                       | diseases.ageOfOnset.iso8601duration                         |
|  CONDITION_OCCURRENCE                                       | condition_concept_id                                       | diseases.diseaseCode                                        |
|  CONDITION_OCCURRENCE                                       | All variables                                              | diseases._info                                              |
|  CONDITION_OCCURRENCE                                       | condition_status_concept_id                                | diseases.stage                                              |
|  CONDITION_OCCURRENCE                                       | person_id, visit_occurrence_id                             | diseases._visit                                             |

## ethnicity
|  OMOP Table(s)                                              | OMOP Variable                                              | BFF JSON path                                               |
|  :---:                                                      | :---:                                                      | :---:                                                       |
|  PERSON                                                     | race_source_value                                          | ethnicity                                                   |

## exposures
|  OMOP Table(s)                                              | OMOP Variable                                              | BFF JSON path                                               |
|  :---:                                                      | :---:                                                      | :---:                                                       |
|  OBSERVATION, PERSON                                        | observation_date, birth_datetime                           | exposures.ageOfAtExposure.iso8601duration                   |
|  OBSERVATION                                                | observation_date                                           | exposures.date                                              |
|                                                             | DEFAULT                                                    | exposures.duration                                          |
|  OBSERVATION                                                | All variables                                              | exposures._info                                             |
|  OBSERVATION                                                | observation_concept_id                                     | exposures.exposureCode                                      |
|  OBSERVATION                                                | unit_concept_id                                            | exposures.unit                                              |
|  OBSERVATION                                                | value_as_number                                            | exposures.value                                             |

## geographicOrigin
|  OMOP Table(s)                                              | OMOP Variable                                              | BFF JSON path                                               |
|  :---:                                                      | :---:                                                      | :---:                                                       |
|  PERSON                                                     | ethnicity_source_value                                     | geographicOrigin                                            |

## id
|  OMOP Table(s)                                              | OMOP Variable                                              | BFF JSON path                                               |
|  :---:                                                      | :---:                                                      | :---:                                                       |
|  PERSON                                                     | person_id                                                  | id                                                          |

## info
|  OMOP Table(s)                                              | OMOP Variable                                              | BFF JSON path                                               |
|  :---:                                                      | :---:                                                      | :---:                                                       |
|  PERSON                                                     | All variables                                              | info                                                        |
|  PERSON                                                     | birth_datetime                                             | info.dateOfBirth                                            |

## interventionsOrProcedures
|  OMOP Table(s)                                              | OMOP Variable                                              | BFF JSON path                                               |
|  :---:                                                      | :---:                                                      | :---:                                                       |
|  PROCEDURE_OCCURRENCE, PERSON                               | procedure_date, birth_datetime                             | interventionsOrProcedures.ageAtProcedure.iso8601duration    |
|  PROCEDURE_OCCURRENCE                                       | procedure_date                                             | interventionsOrProcedures.dateOfProcedure                   |
|  PROCEDURE_OCCURRENCE                                       | All variables                                              | interventionsOrProcedures._info                             |
|  PROCEDURE_OCCURRENCE                                       | procedure_concept_id                                       | interventionsOrProcedures.procedureCode                     |

## karyotypicSex
NA

## measures
|  OMOP Table(s)                                              | OMOP Variable                                              | BFF JSON path                                               |
|  :---:                                                      | :---:                                                      | :---:                                                       |
|  MEASUREMENT                                                | measurement_concept_id                                     | measures.assayCode                                          |
|  MEASUREMENT                                                | measurement_date                                           | measures.date                                               |
|  MEASUREMENT                                                | measurement_concept_id                                     | measures.assayCode                                          |
|  MEASUREMENT                                                | unit_concept_id                                            | measures.measurementValue.quantity.unit                     |
|  MEASUREMENT                                                | value_as_number                                            | measures.measurementValue.quantity.value                    |
|  MEASUREMENT                                                | operator_concept_id, value_as_number, unit_concept_id      | measures.measurementValue.quantity.referenceRange           |
|  MEASUREMENT                                                | All variables                                              | measures._info                                              |
|  MEASUREMENT, PERSON                                        | measurement_date, birth_datetime                           | measures.observationMoment.age.iso8601duration              |
|  MEASUREMENT                                                |                                                            | measures.procedure (= measures.assayCode)                   |
|  MEASUREMENT                                                | person_id, visit_occurrence_id                             | diseases._visit                                             |

## pedigrees
NA

## phenotypicFeatures
|  OMOP Table(s)                                              | OMOP Variable                                              | BFF JSON path                                               |
|  :---:                                                      | :---:                                                      | :---:                                                       |
|  OBSERVATION                                                | observation_concept_id                                     | phenotypicFeatures.featureType                              |
|  OBSERVATION                                                | All variables                                              | phenotypicFeatures._info                                    |
|  OBSERVATION, PERSON                                        | observation_date, birth_datetime                           | phenotypicFeatures.onset.isoduration                        |
|  OBSERVATION                                                | person_id, visit_occurrence_id                             | phenotypicFeatures._visit                                   |

## sex
|  OMOP Table(s)                                              | OMOP Variable                                              | BFF JSON path                                               |
|  :---:                                                      | :---:                                                      | :---:                                                       |
|  PERSON                                                     | gender_concept_id                                          | sex                                                         |

## treatments
|  OMOP Table(s)                                              | OMOP Variable                                              | BFF JSON path                                               |
|  :---:                                                      | :---:                                                      | :---:                                                       |
|  DRUG_EXPOSURE, PERSON                                      | drug_exposure_start_date, birth_datetime                   | treatments.ageOfOnset.age.iso8601duration                   |
|                                                             | DEFAULT                                                    | treatments.date                                             |
|  DRUG_EXPOSURE                                              | All variables                                              | treatments._info                                            |
|                                                             | DEFAULT                                                    | treatments.doseIntervals                                    |
|                                                             | DEFAULT                                                    | treatments.routeOfAdministration                            |
|  DRUG_EXPOSURE                                              | drug_concept_id                                            | treatments.treatmentCode                                    |
|  DRUG_EXPOSURE                                              | person_id, visit_occurrence_id                             | treatments._visit                                           |
