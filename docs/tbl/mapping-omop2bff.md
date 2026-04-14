#### Version 0.30

**Target model:** BFF

**Entity:** individuals

## Terms

### diseases
| Source field | Target field | Notes |
| --- | --- | --- |
| `CONDITION_OCCURRENCE.condition_concept_id` | `diseases.diseaseCode` | Mapped through OHDSI concepts |
| `CONDITION_OCCURRENCE.condition_start_date` + `PERSON.birth_datetime` | `diseases.ageOfOnset` | Derived age |
| `CONDITION_OCCURRENCE.condition_status_concept_id` | `diseases.stage` | Defaulted when absent |
| `CONDITION_OCCURRENCE.*` | `diseases._info.CONDITION_OCCURRENCE.OMOP_columns` | Provenance payload |
| `VISIT_OCCURRENCE` context | `diseases._visit` | Added when visit context is available |

### ethnicity
| Source field | Target field | Notes |
| --- | --- | --- |
| `PERSON.race_source_value` | `ethnicity` | Normalized through ontology lookup |

### exposures
| Source field | Target field | Notes |
| --- | --- | --- |
| `OBSERVATION.observation_concept_id` | `exposures.exposureCode` | Only observations classified as exposures are used |
| `OBSERVATION.observation_date` + `PERSON.birth_datetime` | `exposures.ageAtExposure` | Derived age |
| `OBSERVATION.observation_date` | `exposures.date` | Direct |
| `OBSERVATION.unit_concept_id` | `exposures.unit` | Defaulted when absent |
| `OBSERVATION.value_as_number` | `exposures.value` | `\N` is converted to `-1` |
| `DEFAULT` | `exposures.duration` | Added for Beacon completeness |
| `OBSERVATION.*` | `exposures._info.OBSERVATION.OMOP_columns` | Provenance payload |

### geographicOrigin
| Source field | Target field | Notes |
| --- | --- | --- |
| `PERSON.ethnicity_source_value` | `geographicOrigin` | Normalized through ontology lookup |

### id
| Source field | Target field | Notes |
| --- | --- | --- |
| `PERSON.person_id` | `id` | Stringified in Beacon output |

### info
| Source field | Target field | Notes |
| --- | --- | --- |
| `PERSON.*` | `info.PERSON.OMOP_columns` | Raw OMOP row is preserved |
| `PERSON.birth_datetime` | `info.dateOfBirth` | Timestamp form |
| `metaData` | `info.metaData` | Emitted outside `--test` mode |
| `convertPheno` | `info.convertPheno` | Emitted outside `--test` mode |

### interventionsOrProcedures
| Source field | Target field | Notes |
| --- | --- | --- |
| `PROCEDURE_OCCURRENCE.procedure_concept_id` | `interventionsOrProcedures.procedureCode` | Mapped through OHDSI concepts |
| `PROCEDURE_OCCURRENCE.procedure_date` + `PERSON.birth_datetime` | `interventionsOrProcedures.ageAtProcedure` | Derived age |
| `PROCEDURE_OCCURRENCE.procedure_date` | `interventionsOrProcedures.dateOfProcedure` | Direct |
| `DEFAULT` | `interventionsOrProcedures.bodySite` | Added for Beacon completeness |
| `PROCEDURE_OCCURRENCE.*` | `interventionsOrProcedures._info.PROCEDURE_OCCURRENCE.OMOP_columns` | Provenance payload |
| `VISIT_OCCURRENCE` context | `interventionsOrProcedures._visit` | Added when visit context is available |

### karyotypicSex
NA

### measures
| Source field | Target field | Notes |
| --- | --- | --- |
| `MEASUREMENT.measurement_concept_id` | `measures.assayCode` | Mapped through OHDSI concepts |
| `MEASUREMENT.measurement_date` | `measures.date` | Direct |
| `MEASUREMENT.value_as_concept_id` | `measures.measurementValue` | Used for ontology-valued measurements |
| `MEASUREMENT.value_as_number` | `measures.measurementValue.quantity.value` | Used for numeric measurements |
| `MEASUREMENT.unit_concept_id` | `measures.measurementValue.quantity.unit` | Defaulted when absent |
| `MEASUREMENT.operator_concept_id` + numeric value + unit | `measures.measurementValue.quantity.referenceRange` | Derived range payload |
| `MEASUREMENT.measurement_date` + `PERSON.birth_datetime` | `measures.observationMoment` | Derived age |
| `MEASUREMENT.measurement_date` + `PERSON.birth_datetime` | `measures.procedure.ageAtProcedure` | Mirrors `observationMoment` |
| `MEASUREMENT.measurement_date` | `measures.procedure.dateOfProcedure` | Direct |
| `MEASUREMENT.measurement_type_concept_id` | `measures.procedure.procedureCode` | Mapped through OHDSI concepts |
| `DEFAULT` | `measures.procedure.bodySite` | Added for Beacon completeness |
| `MEASUREMENT.*` | `measures._info.MEASUREMENT.OMOP_columns` | Provenance payload |
| `VISIT_OCCURRENCE` context | `measures._visit` | Added when visit context is available |

### pedigrees
NA

### phenotypicFeatures
| Source field | Target field | Notes |
| --- | --- | --- |
| `OBSERVATION.observation_concept_id` | `phenotypicFeatures.featureType` | Only non-exposure observations are used |
| `OBSERVATION.observation_date` + `PERSON.birth_datetime` | `phenotypicFeatures.onset` | Derived age |
| `OBSERVATION.*` | `phenotypicFeatures._info.OBSERVATION.OMOP_columns` | Provenance payload |
| `VISIT_OCCURRENCE` context | `phenotypicFeatures._visit` | Added when visit context is available |

### sex
| Source field | Target field | Notes |
| --- | --- | --- |
| `PERSON.gender_concept_id` | `sex` | Mapped through OHDSI concepts and then normalized to Beacon terms |

### treatments
| Source field | Target field | Notes |
| --- | --- | --- |
| `DRUG_EXPOSURE.drug_concept_id` | `treatments.treatmentCode` | Mapped through OHDSI concepts |
| `DRUG_EXPOSURE.drug_exposure_start_date` + `PERSON.birth_datetime` | `treatments.ageAtOnset` | Derived age |
| `DEFAULT` | `treatments.routeOfAdministration` | Placeholder |
| `DEFAULT` | `treatments.doseIntervals` | Initialized as an empty list |
| `DRUG_EXPOSURE.*` | `treatments._info.DRUG_EXPOSURE.OMOP_columns` | Provenance payload |
| `VISIT_OCCURRENCE` context | `treatments._visit` | Added when visit context is available |
