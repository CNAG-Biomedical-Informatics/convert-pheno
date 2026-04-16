#### Version 0.31

**Target model:** BFF

**Entity:** individuals

## Terms

### id
| Source field | Target field | Notes |
| --- | --- | --- |
| `patient.id` | `id` | Preferred patient envelope id |
| `id` | `id` | Accepted top-level envelope id |
| `ehr_status.subject.external_ref.id.value` | `id` | Accepted patient identifier from `ehr_status` |
| `ehr_id.value` / `ehr_id` | `id` | Accepted openEHR envelope identifier after `ehr_status.subject.external_ref.id.value` |
| `PARTY_SELF.external_ref.id.value` | `id` | Accepted when present inside a canonical composition |
| multiple input documents with the same resolved patient id | one `individual.id` | Compositions are grouped before mapping |
| raw composition arrays with multiple embedded patient ids | multiple `individual.id` values | Split only by embedded patient-scoped identifiers; composition-level ids are ignored |
| missing resolvable patient id | none | Conversion fails |

### sex
| Source field | Target field | Notes |
| --- | --- | --- |
| administrative gender code `male` | `sex` | Mapped to `NCIT:C20197` / `Male` |
| administrative gender code `female` | `sex` | Mapped to `NCIT:C16576` / `Female` |
| missing administrative gender | none | Conversion fails |

### info
| Source field | Target field | Notes |
| --- | --- | --- |
| `compositions[]` | `info.openehr.compositions` | Full canonical source compositions are preserved |
| multiple documents for the same patient | `info.openehr.compositions` | Concatenated into one patient-scoped list |
| generated conversion metadata | `info.convertPheno` | Added unless `--test` is used |

### diseases
| Source field | Target field | Notes |
| --- | --- | --- |
| `openEHR-EHR-EVALUATION.problem_diagnosis.v1 / ELEMENT["Problem/Diagnosis name"]` | `diseases.diseaseCode` | `DV_CODED_TEXT` keeps its external CURIE; `DV_TEXT` gets a synthetic `openEHR:` id |
| source evaluation node | `diseases._info.openEHR` | Exact source node is preserved for provenance |

### measures
| Source field | Target field | Notes |
| --- | --- | --- |
| `openEHR-EHR-OBSERVATION.lab_test-result.v1` or `openEHR-EHR-OBSERVATION.laboratory_test_result.v1` / `ELEMENT["Test result name"|"Test name"|"Analyte name"]` | `measures.assayCode` | `DV_CODED_TEXT` keeps its external CURIE; `DV_TEXT` gets a synthetic `openEHR:` id |
| same laboratory observation / `ELEMENT["Result value"]` | `measures.measurementValue.quantity` | Quantity value and unit are preserved |
| same laboratory observation / first available datetime | `measures.timeObserved.timestamp` | Timestamp is preserved when found |
| `openEHR-EHR-OBSERVATION.body_temperature.v2 / ELEMENT["Temperatur"]` | `measures.measurementValue.quantity` | Mapped as a first-class measurement |
| `openEHR-EHR-OBSERVATION.body_temperature.v2 / node name` | `measures.assayCode` | Uncoded node names become synthetic `openEHR:` ids |
| measurement source node | `measures._info.openEHR` | Exact source node is preserved for provenance |
| observation without a usable quantity | none | Skipped |

### phenotypicFeatures
| Source field | Target field | Notes |
| --- | --- | --- |
| `openEHR-EHR-OBSERVATION.symptom_sign_screening.v0 / ELEMENT["Bezeichnung des Symptoms oder Anzeichens."]` | `phenotypicFeatures.featureType` | Falls back to the node name when the explicit symptom label is absent |
| same observation / `ELEMENT["Vorhanden?"]` | `phenotypicFeatures.excluded` | Present symptoms map to `false`, absent symptoms map to `true` |
| phenotypic feature source node | `phenotypicFeatures._info.openEHR` | Exact source node is preserved for provenance |

### interventionsOrProcedures
| Source field | Target field | Notes |
| --- | --- | --- |
| `openEHR-EHR-ACTION.procedure.v1 / ELEMENT["Procedure name"]` | `interventionsOrProcedures.procedureCode` | `DV_TEXT` becomes a synthetic `openEHR:` id |
| same procedure action / `ELEMENT["Body site"]` | `interventionsOrProcedures.bodySite` | Preserved when present |
| same procedure action / `time.value` | `interventionsOrProcedures.dateOfProcedure` | Date only |
| procedure source node | `interventionsOrProcedures._info.openEHR` | Exact source node is preserved for provenance |

### treatments
| Source field | Target field | Notes |
| --- | --- | --- |
| `openEHR-EHR-ACTION.medication.v1 / ELEMENT["Name"|"Medication item"|"Immunisation item"]` | `treatments.treatmentCode` | `DV_TEXT` becomes a synthetic `openEHR:` id |
| same medication action / `ELEMENT["Route"]` | `treatments.routeOfAdministration` | Preserved when present |
| treatment source node | `treatments._info.openEHR` | Exact source node is preserved for provenance |

## Current omissions

The current experimental mapper does **not** yet emit first-class Beacon fields such as:

- `ethnicity`
- `exposures`
- `geographicOrigin`
- `karyotypicSex`
- `biosamples`

Those source details remain only in the preserved `info.openehr.compositions` payload unless and until explicit mappings are added.
