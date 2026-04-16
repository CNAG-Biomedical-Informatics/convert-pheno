## Provenance

These example inputs were copied from the `ehrbase/openEHR_SDK` repository,
specifically from its test-data module under canonical composition JSON:

- repository: <https://github.com/ehrbase/openEHR_SDK>
- source directory:
  `test-data/src/main/resources/composition/canonical_json/`

Copied files:

- `ips_canonical.json`
- `laboratory_report.json`
- `gecco_personendaten.json`
- `compo_corona.json`

Derived local fixture:

- `gecco_personendaten_patient.json`
  Derived from `gecco_personendaten.json` by adding
  `subject.external_ref.id.value = openehr-patient-2`
  for patient-identified openEHR input tests.

## Note

In the current `openEHR -> BFF` mapper, terms with an external
`defining_code` keep that CURIE (for example `LOINC:2093-3`), while uncoded
`DV_TEXT` terms are emitted with synthetic `openEHR:` ids so BFF ontology
terms still have both `id` and `label`.
