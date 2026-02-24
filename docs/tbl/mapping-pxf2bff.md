#### Version 0.25

# Terms

## diseases
|  PXF JSON path                                              | BFF JSON path                                               |
|  :---:                                                      | :---:                                                       |
|  diseases                                                   | diseases                                                    |
|  diseases.term                                              | diseases.diseaseCode                                        |
|  diseases.onset                                             | diseases.ageOfOnset                                         |


## ethnicity
NA

## geographicOrigin
NA

## id
|  PXF JSON path                                              | BFF JSON path                                               |
|  :---:                                                      | :---:                                                       |
|  subject.id                                                 | id                                                          |

## info
|  PXF JSON path                                              | BFF JSON path                                               |
|  :---:                                                      | :---:                                                       |
|  dateOfBirth, genes, metaData, variants, interpretations, files, biosample | info                                                        |

## interventionsOrProcedures
|  PXF JSON path                                              | BFF JSON path                                               |
|  :---:                                                      | :---:                                                       |
|  medicalActions.procedure                                   | interventionsOrProcedures                                   |
|  medicalActions.procedure.code                              | interventionsOrProcedures.procedureCode                     |
|  medicalActions.procedure.performed                         | interventionsOrProcedures.ageAtProcedure                    |

## karyotypicSex
|  PXF JSON path                                              | BFF JSON path                                               |
|  :---:                                                      | :---:                                                       |
|  subject.karyotypicSex                                      | karyotypicSex                                               |

## measures
|  PXF JSON path                                              | BFF JSON path                                               |
|  :---:                                                      | :---:                                                       |
|  measurements                                               | measures                                                    |
|  measurements.assay                                         | measures.assayCode                                          |
|  measurements.value                                         | measures.measurementValue                                   |
|  measurements.complexValue.typedQuantities.type             | measures.measurementValue.typedQuantities.quantityType      |
|  measurements.timeObserved                                  | measures.observationMoment                                  |
|  measurements.procedure                                     | measures.procedure                                          |


## pedigrees
NA

## phenotypicFeatures
|  PXF JSON path                                              | BFF JSON path                                               |
|  :---:                                                      | :---:                                                       |
|  phenotypicFeatures                                         | phenotypicFeatures                                          |
|  phenotypicFeatures.type                                    | phenotypicFeatures.featureType                              |
|  phenotypicFeatures.negated                                 | phenotypicFeatures.excluded                                 |
|  phenotypicFeatures.evidence (array)                        | phenotypicFeatures.evidence (v2.0.0 is still object)        |

## sex
|  PXF JSON path                                              | BFF JSON path                                               |
|  :---:                                                      | :---:                                                       |
|  subject.sex                                                | sex                                                         |

## treatments
|  PXF JSON path                                              | BFF JSON path                                               |
|  :---:                                                      | :---:                                                       |
|  medicalActions.treatment                                   | treatments                                                  |
|  medicalActions.treatment.agent                             | treatments.treatmentCode                                    |
