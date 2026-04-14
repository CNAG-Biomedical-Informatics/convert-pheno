#### Version 0.30

**Target model:** BFF

**Entities:** individuals, biosamples

!!! Note
    Field names in the tables use the canonical `camelCase` JSON form used by Beacon and Phenopackets examples. The parser may still accept some protobuf-style `snake_case` aliases on input for compatibility, but those aliases are not documented as the primary form here.

## Individuals

### diseases
| Source field | Target field | Notes |
| --- | --- | --- |
| `diseases.term` | `diseases.diseaseCode` | Renamed ontology term |
| `diseases.onset` | `diseases.ageOfOnset` | Supported Phenopackets time elements are unwrapped |

### ethnicity
NA

### exposures
| Source field | Target field | Notes |
| --- | --- | --- |
| `exposures.type` | `exposures.exposureCode` | Legacy PXF field; renamed |
| `exposures.occurrence.timestamp` | `exposures.date` | Date only |
| `exposures.occurrence.age` | `exposures.ageAtExposure` | Unwrapped when present |
| `exposures.occurrence` | `exposures.info.phenopacket.occurrence` | Preserved when not directly representable |
| `exposures.value` | `exposures.value` | Preserved when present |
| `exposures.unit` | `exposures.unit` | Preserved when present; defaulted when absent |
| `DEFAULT` | `exposures.duration` | Added for Beacon validation |

### geographicOrigin
NA

### id
| Source field | Target field | Notes |
| --- | --- | --- |
| `subject.id` | `id` | Direct |

### info
| Source field | Target field | Notes |
| --- | --- | --- |
| `subject.dateOfBirth` | `info.phenopacket.dateOfBirth` | Preserved; top-level alias is also accepted |
| `genes` | `info.phenopacket.genes` | Preserved |
| `interpretations` | `info.phenopacket.interpretations` | Preserved |
| `metaData` | `info.phenopacket.metaData` | Preserved |
| `variants` | `info.phenopacket.variants` | Preserved |
| `files` | `info.phenopacket.files` | Preserved |
| `pedigree` | `info.phenopacket.pedigree` | Preserved |
| `biosamples` | `info.phenopacket.biosamples` | Preserved in the legacy individuals-only output path |

### interventionsOrProcedures
| Source field | Target field | Notes |
| --- | --- | --- |
| `medicalActions.procedure.code` | `interventionsOrProcedures.procedureCode` | Renamed |
| `medicalActions.procedure.performed.age` | `interventionsOrProcedures.ageAtProcedure` | Unwrapped age form |
| `medicalActions.procedure.performed.ageRange` | `interventionsOrProcedures.ageAtProcedure` | Unwrapped age-range form |
| `medicalActions.procedure.performed.gestationalAge` | `interventionsOrProcedures.ageAtProcedure` | Unwrapped gestational-age form |
| `medicalActions.procedure.performed.interval` | `interventionsOrProcedures.ageAtProcedure` | Unwrapped interval form |
| `medicalActions.procedure.performed.ontologyClass` | `interventionsOrProcedures.ageAtProcedure` | Unwrapped ontology-term form |
| `medicalActions.procedure.performed.timestamp` | `interventionsOrProcedures.dateOfProcedure` | Date only |
| `medicalActions.procedure.performed` | `interventionsOrProcedures.info.phenopacket.performed` | Preserved when not mapped directly |

### karyotypicSex
| Source field | Target field | Notes |
| --- | --- | --- |
| `subject.karyotypicSex` | `karyotypicSex` | Direct |

### measures
| Source field | Target field | Notes |
| --- | --- | --- |
| `measurements.assay` | `measures.assayCode` | Renamed |
| `measurements.value` | `measures.measurementValue` | Direct value |
| `measurements.complexValue` | `measures.measurementValue` | Used when `value` is absent |
| `measurements.complexValue.typedQuantities.type` | `measures.measurementValue.typedQuantities.quantityType` | Inner key renamed |
| `measurements.timeObserved` | `measures.observationMoment` | Supported Phenopackets time elements are unwrapped |
| `measurements.procedure` | `measures.procedure` | Nested procedure is remapped with the same rules |

### pedigrees
NA

### phenotypicFeatures
| Source field | Target field | Notes |
| --- | --- | --- |
| `phenotypicFeatures.type` | `phenotypicFeatures.featureType` | Renamed |
| `phenotypicFeatures.negated` | `phenotypicFeatures.excluded` | Renamed to the Beacon field |
| `phenotypicFeatures.onset` | `phenotypicFeatures.onset` | Supported Phenopackets time elements are unwrapped |
| `phenotypicFeatures.evidence[0]` | `phenotypicFeatures.evidence` | Beacon individuals expects one object |
| `phenotypicFeatures.evidence[]` | `phenotypicFeatures.evidence.info.phenopacket.evidence` | Full source array is preserved |

### sex
| Source field | Target field | Notes |
| --- | --- | --- |
| `subject.sex` | `sex` | Normalized through ontology lookup |

### treatments
| Source field | Target field | Notes |
| --- | --- | --- |
| `medicalActions.treatment.agent` | `treatments.treatmentCode` | Renamed |
| `medicalActions.treatment.routeOfAdministration` | `treatments.routeOfAdministration` | Preserved |
| `medicalActions.treatment.doseIntervals` | `treatments.doseIntervals` | Preserved; nested defaults may be added for validation |

## Biosamples

These rows apply when `PXF` biosamples are emitted as a first-class Beacon `biosamples` entity.

### biosamples
| Source field | Target field | Notes |
| --- | --- | --- |
| `biosamples.id` | `biosamples.id` | Direct |
| `biosamples.individualId` | `biosamples.individualId` | Direct |
| `biosamples.materialSample` | `biosamples.biosampleStatus` | Renamed; defaulted when absent |
| `biosamples.sampleType` | `biosamples.sampleOriginType` | Renamed; defaulted when absent |
| `biosamples.sampledTissue` | `biosamples.sampleOriginDetail` | Renamed |
| `biosamples.timeOfCollection.timestamp` | `biosamples.collectionDate` | Date only |
| `biosamples.timeOfCollection.interval.start` | `biosamples.collectionDate` | Start date only |
| `biosamples.timeOfCollection.age.iso8601duration` | `biosamples.collectionMoment` | Age at collection |
| `biosamples.description` | `biosamples.notes` | Renamed free text |
| `biosamples.diagnosticMarkers` | `biosamples.diagnosticMarkers` | Direct |
| `biosamples.histologicalDiagnosis` | `biosamples.histologicalDiagnosis` | Direct |
| `biosamples.pathologicalStage` | `biosamples.pathologicalStage` | Direct |
| `biosamples.pathologicalTnmFinding` | `biosamples.pathologicalTnmFinding` | Direct |
| `biosamples.tumorGrade` | `biosamples.tumorGrade` | Direct |
| `biosamples.tumorProgression` | `biosamples.tumorProgression` | Direct |
| `biosamples.sampleProcessing` | `biosamples.sampleProcessing` | Direct |
| `biosamples.sampleStorage` | `biosamples.sampleStorage` | Direct |
| `biosamples.phenotypicFeatures.type` | `biosamples.phenotypicFeatures.featureType` | Renamed |
| `biosamples.phenotypicFeatures.evidence[].reference.description` | `biosamples.phenotypicFeatures.evidence[].reference.notes` | Renamed |
| `biosamples.measurements.assay` | `biosamples.measurements.assayCode` | Renamed |
| `biosamples.measurements.value` | `biosamples.measurements.measurementValue` | Direct value |
| `biosamples.measurements.complexValue` | `biosamples.measurements.measurementValue` | Used when `value` is absent |
| `biosamples.measurements.timeObserved` | `biosamples.measurements.observationMoment` | Renamed |
| `biosamples.procedure.code` | `biosamples.obtentionProcedure.procedureCode` | Renamed |
| `biosamples.procedure.performed.age` | `biosamples.obtentionProcedure.ageAtProcedure` | Unwrapped age form |
| `biosamples.procedure.performed.timestamp` | `biosamples.obtentionProcedure.dateOfProcedure` | Date only |
| `biosamples.derivedFromId` | `biosamples.info.phenopacket.derivedFromId` | Preserved |
| `biosamples.files` | `biosamples.info.phenopacket.files` | Preserved |
| `biosamples.taxonomy` | `biosamples.info.phenopacket.taxonomy` | Preserved |
| `biosamples.timeOfCollection` | `biosamples.info.phenopacket.timeOfCollection` | Raw source payload is preserved |
| `biosamples.procedure` | `biosamples.info.phenopacket.procedure` | Raw source payload is preserved |
| `biosamples.measurements` | `biosamples.info.phenopacket.measurements` | Raw source payload is preserved |
