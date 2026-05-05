#### Version 0.31

**Target model:** BFF

**Entity:** individuals, biosamples

By default, raw OMOP rows are preserved under `OMOP_columns` provenance blocks so
converted `BFF` can be audited against the source data and source-specific OMOP
values remain queryable. Use `--no-source-info` to omit these raw provenance
payloads.

## Terms

### diseases
| Source field | Target field | Notes |
| --- | --- | --- |
| `CONDITION_OCCURRENCE.condition_concept_id` | `diseases.diseaseCode` | Mapped through OHDSI concepts |
| `CONDITION_OCCURRENCE.condition_start_date` + `PERSON.birth_datetime` | `diseases.ageOfOnset` | Derived age |
| `CONDITION_OCCURRENCE.condition_status_concept_id` | `diseases.stage` | Defaulted when absent |
| `CONDITION_OCCURRENCE.*` | `diseases._info.CONDITION_OCCURRENCE.OMOP_columns` | Provenance payload |
| `VISIT_OCCURRENCE` context | `diseases._visit` | Added when visit context is available |
| missing `CONDITION_OCCURRENCE.condition_status_concept_id` | `diseases.stage` | Defaults to `NCIT:C126101` / `Not Available` |

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
| missing `OBSERVATION.unit_concept_id` | `exposures.unit` | Defaults to `NCIT:C126101` / `Not Available` |
| `DEFAULT` | `exposures.duration` | Defaults to `P0Y` in the OMOP-specific path |
| `OBSERVATION.value_as_number = \N` | `exposures.value` | Defaults to `-1` |

### geographicOrigin
| Source field | Target field | Notes |
| --- | --- | --- |
| `OBSERVATION.value_as_concept_id` | `geographicOrigin` | Preferred when the observation represents `Country of birth`; normalized through ontology lookup |
| `OBSERVATION.value_as_string` | `geographicOrigin` | Preferred string fallback when the observation represents `Country of birth` |
| `OBSERVATION.value_source_value` | `geographicOrigin` | Preferred string fallback when the observation represents `Country of birth` |
| `PERSON.ethnicity_source_value` | `geographicOrigin` | Fallback when no `Country of birth` observation can be resolved |

### id
| Source field | Target field | Notes |
| --- | --- | --- |
| `PERSON.person_id` | `id` | Stringified in Beacon output |

### info
| Source field | Target field | Notes |
| --- | --- | --- |
| `PERSON.*` | `info.PERSON.OMOP_columns` | Raw OMOP row is preserved |
| `PERSON.birth_datetime` | `info.dateOfBirth` | Timestamp form |
| `convertPheno` | `info.convertPheno` | Emitted outside `--test` mode |
| missing `PERSON.gender_concept_id` | none | The participant is skipped entirely in this direction |

### interventionsOrProcedures
| Source field | Target field | Notes |
| --- | --- | --- |
| `PROCEDURE_OCCURRENCE.procedure_concept_id` | `interventionsOrProcedures.procedureCode` | Mapped through OHDSI concepts |
| `PROCEDURE_OCCURRENCE.procedure_date` + `PERSON.birth_datetime` | `interventionsOrProcedures.ageAtProcedure` | Derived age |
| `PROCEDURE_OCCURRENCE.procedure_date` | `interventionsOrProcedures.dateOfProcedure` | Direct |
| `DEFAULT` | `interventionsOrProcedures.bodySite` | Added for Beacon completeness |
| `PROCEDURE_OCCURRENCE.*` | `interventionsOrProcedures._info.PROCEDURE_OCCURRENCE.OMOP_columns` | Provenance payload |
| `VISIT_OCCURRENCE` context | `interventionsOrProcedures._visit` | Added when visit context is available |
| `DEFAULT` | `interventionsOrProcedures.bodySite` | Defaults to `NCIT:C126101` / `Not Available` |

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
| missing `MEASUREMENT.unit_concept_id` | `measures.measurementValue.quantity.unit` | Defaults to `NCIT:C126101` / `Not Available` |
| `MEASUREMENT.value_as_number = \N` and no `value_as_concept_id` | `measures.measurementValue.quantity` | Defaults to quantity `-1` with `Not Available` unit and `-1/-1` reference range |
| missing `MEASUREMENT.measurement_concept_id` | none | The row is skipped rather than emitting a default measure |
| `DEFAULT` | `measures.procedure.bodySite` | Defaults to `NCIT:C126101` / `Not Available` |

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
| missing `PERSON.gender_concept_id` | none | The participant is skipped before an individual is emitted |

### treatments
| Source field | Target field | Notes |
| --- | --- | --- |
| `DRUG_EXPOSURE.drug_concept_id` | `treatments.treatmentCode` | Mapped through OHDSI concepts |
| `DRUG_EXPOSURE.drug_exposure_start_date` + `PERSON.birth_datetime` | `treatments.ageAtOnset` | Derived age |
| `DEFAULT` | `treatments.routeOfAdministration` | Placeholder |
| `DEFAULT` | `treatments.doseIntervals` | Initialized as an empty list |
| `DRUG_EXPOSURE.*` | `treatments._info.DRUG_EXPOSURE.OMOP_columns` | Provenance payload |
| `VISIT_OCCURRENCE` context | `treatments._visit` | Added when visit context is available |
| `DEFAULT` | `treatments.routeOfAdministration` | Defaults to `NCIT:C126101` / `Not Available` |
| `DEFAULT` | `treatments.doseIntervals` | Defaults to an empty list |

## Biosamples

### biosamples
| Source field | Target field | Notes |
| --- | --- | --- |
| `SPECIMEN.specimen_id` | `biosamples.id` | Stringified in Beacon output |
| `SPECIMEN.person_id` | `biosamples.individualId` | Stringified in Beacon output |
| `SPECIMEN.specimen_concept_id` | `biosamples.sampleOriginType` | Mapped through OHDSI concepts; defaulted when absent |
| `SPECIMEN.anatomic_site_concept_id` | `biosamples.sampleOriginDetail` | Mapped through OHDSI concepts when present |
| `SPECIMEN.specimen_type_concept_id` | `biosamples.obtentionProcedure.procedureCode` | Mapped through OHDSI concepts when present |
| `SPECIMEN.specimen_date` | `biosamples.collectionDate` | Direct |
| `SPECIMEN.specimen_date` + `PERSON.birth_datetime` | `biosamples.collectionMoment` | Derived age |
| `SPECIMEN.disease_status_concept_id` | `biosamples.histologicalDiagnosis` | Mapped through OHDSI concepts when present |
| `SPECIMEN.quantity` | `biosamples.measurements.measurementValue.quantity.value` | Emitted as a sample-level measurement when numeric |
| `SPECIMEN.unit_concept_id` | `biosamples.measurements.measurementValue.quantity.unit` | Mapped through OHDSI concepts when present |
| `SPECIMEN.unit_source_value` | `biosamples.measurements.measurementValue.quantity.unit.label` | Used as fallback unit label when no unit concept is available |
| `OMOP:SPECIMEN.quantity` | `biosamples.measurements.assayCode` | Local valid CURIE identifying the OMOP source field; OMOP `SPECIMEN` has no `measurement_concept_id` equivalent |
| `SPECIMEN.specimen_source_id` / `SPECIMEN.specimen_source_value` | none | Kept only in provenance; not promoted to Beacon schema fields by default |
| `DEFAULT` | `biosamples.biosampleStatus` | Defaulted for Beacon completeness |
| `convertPheno` | `biosamples.info.convertPheno` | Emitted outside `--test` mode |
| `SPECIMEN.*` | `biosamples.info.SPECIMEN.OMOP_columns` | Provenance payload |
| missing `SPECIMEN.specimen_concept_id` | `biosamples.sampleOriginType` | Defaults to `NCIT:C126101` / `Not Available` |
| `DEFAULT` | `biosamples.biosampleStatus` | Defaults to `NCIT:C126101` / `Not Available` |

`SPECIMEN.quantity` is promoted conservatively. OMOP provides the value and unit,
but the `SPECIMEN` table does not include a `measurement_concept_id` equivalent
for the measured sample property. For this reason, `Convert-Pheno` uses the
valid local CURIE `OMOP:SPECIMEN.quantity` with label `Specimen quantity` as the
Beacon `assayCode`, while the original OMOP columns remain available under
`biosamples.info.SPECIMEN.OMOP_columns`.
