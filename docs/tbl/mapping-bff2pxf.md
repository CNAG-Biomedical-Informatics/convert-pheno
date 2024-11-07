#### Version 0.25

# Terms

## id
|  BFF JSON path                                              | PXF JSON path                                               |
|  :---:                                                      | :---:                                                       |
|  (UNIQUE ID)                                                | id                                                          |

## subject
|  BFF JSON path                                              | PXF JSON path                                               |
|  :---:                                                      | :---:                                                       |
|  id                                                         | subject.id                                                  |
|  (ALIVE)                                                    | subject.vitalStatus                                         |
|  sex.label                                                  | subject.sex                                                 |
|  info.dateOfBirth                                           | subject.dateOfBirth                                         |
|  karyotypicSex                                              | subject.karyotypicSex                                       |

## phenotypicFeatures
|  BFF JSON path                                              | PXF JSON path                                               |
|  :---:                                                      | :---:                                                       |
|  phenotypicFeatures.featureType                             | phenotypicFeatures.type                                     |
|  phenotypicFeatures.excluded                                | phenotypicFeatures.excluded                                 |


## measurements
|  BFF JSON path                                              | PXF JSON path                                               |
|  :---:                                                      | :---:                                                       |
|  measures.assayCode                                         | measurements.assay                                          |
|  measures.measurementValue                                  | measurements.value                                          |
|  measures.measurementValue.typedQuantities.quantityType     | measurements.complexValue.typedQuantities.type              |

## biosamples
|  BFF JSON path                                              | PXF JSON path                                               |
|  :---:                                                      | :---:                                                       |
|  info.biosamples                                            | biosamples                                                  |

## interpretations
|  BFF JSON path                                              | PXF JSON path                                               |
|  :---:                                                      | :---:                                                       |
|  info.interpretations                                       | interpretations                                             |

## diseases
|  BFF JSON path                                              | PXF JSON path                                               |
|  :---:                                                      | :---:                                                       |
|  diseases.diseaseCode                                       | diseases.term                                               |
|  diseases.ageOfOnset                                        | diseases.onset                                              |

## medicalActions
|  BFF JSON path                                              | PXF JSON path                                               |
|  :---:                                                      | :---:                                                       |
|  interventionsOrProcedures.procedureCode                    | medicalActions.procedure.code                               |
|  interventionsOrProcedures.ageAtProcedure                   | medicalActions.procedure.performed                          |
|  treatments.treatmentCode                                   | medicalActions.treatment.agent                              |

## files
NA

## metaData
|  BFF JSON path                                              | PXF JSON path                                               |
|  :---:                                                      | :---:                                                       |
|  info.metaData                                              | metaData                                                    |

## exposures (not-listed in PXF documentation)
|  BFF JSON path                                              | PXF JSON path                                               |
|  :---:                                                      | :---:                                                       |
|  exposures.exposureCode                                     | exposures.type                                              |
|  exposures.date                                             | exposures.occurrence.timestamp                              |
