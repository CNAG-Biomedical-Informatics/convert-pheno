---
title: Mapping File
sidebar_label: Mapping File
---

The mapping file is the typed source-to-Beacon contract used by `csv2*`,
`redcap2*`, and `cdiscodm2*` routes. YAML and JSON are accepted, including their
gzip-compressed forms.

For a guided example, start with [Working with Mapping Files](../mapping-files).

## Version Contract

| Key | Required value | Purpose |
| --- | --- | --- |
| `mappingVersion` | `2` | Selects the Convert-Pheno mapping language |
| `target.model` | `beacon` | Identifies the target data model |
| `target.schemaVersion` | `'2.0.0'` | Selects the supported Beacon/BFF schema |
| `project.version` | Project-defined string | Tracks revisions of the project mapping |

These versions are independent. Changing `project.version` does not change the
mapping grammar or Beacon schema.

:::warning[Pre-V2 mappings]
Pre-V2 mappings are rejected. There is no compatibility interpreter for keys
such as `fieldTermLabels`, `valueTermLabels`, `targetFields`, or
`baselineFieldsToPropagate`.
:::

## Top-Level Sections

| Section | Required | Contents |
| --- | --- | --- |
| `mappingVersion` | Yes | Mapping language version |
| `source.profile` | Yes | Normalized record profile: `csv` or `redcap` |
| `target` | Yes | `model` and `schemaVersion` |
| `project` | Yes | `id`, `version`, and optional `description` |
| `defaults` | Yes | Default `ontology` |
| `records` | Yes | Optional `visitId` and `baseline` behavior |
| `beacon.individuals` | Yes | Individual mapping; `id` and `sex` are required |
| `beacon.biosamples` | No | First-class biosample rules |
| `beacon.datasets` | No | Defaults for synthesized datasets |
| `beacon.cohorts` | No | Defaults for synthesized cohorts |

Supported default ontologies are `ncit`, `icd10`, `ohdsi`, `cdisc`, `omim`,
and `hpo`. A term rule can override the project default with its own
`ontology`.

`source.profile` describes the records consumed by the mapping. It does not
select the CLI or API input route. CDISC-ODM records are normalized to the
REDCap representation before mapping, so both routes use `profile: redcap`.
The mapping rules remain source-specific: exports with different item
identifiers require a corresponding dictionary and mapping.

## Source Selectors

Entity rules select one source field and can add conditions:

```yaml
sourceField: smoking
optional: true
when:
  notValues: [No, unknown]
```

| Key | Meaning |
| --- | --- |
| `sourceField` | Source column evaluated by the rule |
| `optional` | Allows the column and other source fields inside that rule to be absent from the input header |
| `when.nonEmpty` | Requires a non-empty value |
| `when.values` | Accepts only the listed values |
| `when.notValues` | Rejects the listed values |

`optional` describes schema variation between compatible exports. It should
not be used to hide a misspelled required column.

Repeated Beacon sections use an ordered `rules` array:

```yaml
phenotypicFeatures:
  rules:
    - sourceField: symptom
      when: { nonEmpty: true }
      featureType:
        ontology: hpo
        query: { from: value }
```

Every rule keeps the source selector and its target Beacon properties in one
object. This avoids parallel field lists whose entries can silently drift out
of alignment.

## Shared Defaults

A repeated section can define target `defaults` shared by its rules:

```yaml
interventionsOrProcedures:
  defaults:
    bodySite: { query: Intestine }
  rules:
    - sourceField: colectomy
      procedureCode: { query: Colectomy }
    - sourceField: ileostomy
      procedureCode: { query: Ileostomy }
```

Defaults are recursively merged into each rule. Rule values win, arrays
replace inherited arrays, and a `null` rule value removes an optional inherited
property. Source keys such as `sourceField`, `optional`, and `when` cannot be
placed in `defaults`; conditions remain local and reviewable.

## Ontology Terms

A target ontology term can be resolved by query or supplied directly.

```yaml
featureType:
  ontology: hpo
  query:
    from: value
    aliases:
      Joint limitation: Limitation of joint mobility
```

| Key | Meaning |
| --- | --- |
| `query.from: value` | Uses the normalized source value |
| `query.from: field` | Uses the source field name |
| `query.from: fieldNote` | Uses the REDCap dictionary field note |
| `query: Label` | Uses one fixed query label |
| `query.aliases` | Rewrites known source labels before lookup |
| `ontology` | Overrides `defaults.ontology` for this term |
| `term` | Supplies one curated `{id, label}` object and bypasses lookup |
| `terms` | Supplies curated terms keyed by possible source query values |

Ontology term IDs must be CURIE-like strings such as `NCIT:C17610` or
`HP:0001388`. Use `term` or `terms` only when the identifier and label are
already curated.

## Scalar Values

Non-ontology target values use one of these forms:

| Form | Result |
| --- | --- |
| `{ from: sourceValue }` | Uses the current rule's source value |
| `{ from: individualId }` | Uses the generated BFF individual ID |
| `{ sourceField: age }` | Uses another named source field |
| `{ literal: value }` | Uses a fixed string, number, or boolean |

These forms do not perform ontology lookup. By contrast, `query.from` selects
the text passed to ontology resolution: `query: { from: value }` searches with
the current source value, rather than copying that value directly into BFF.

## Records

`records.visitId.sourceField` adds visit provenance to mapped repeated terms.
Visit composite keys include the generated individual ID so they remain unique
between participants.

`records.baseline` supports the `firstNonNull` strategy:

```yaml
records:
  baseline:
    strategy: firstNonNull
    sourceFields: [sex, ethnicity, diagnosis]
```

The first non-empty value for each listed field and individual is available to
later rows. This working value does not replace the original value stored in
source provenance.

## Individuals

`beacon.individuals.id` defines ID construction:

```yaml
id:
  sourceFields: [record_id, event_name]
  primaryKey: record_id
  separator: ':'
  missingValue: NA
```

The supported BFF individual sections are:

| Section | Rule shape | Main target properties |
| --- | --- | --- |
| `sex`, `ethnicity`, `geographicOrigin` | One term rule | Corresponding ontology term |
| `karyotypicSex` | One scalar rule | Corresponding scalar value |
| `diseases.rules[]` | Repeated rule | `diseaseCode`, `ageOfOnset`, `familyHistory` |
| `exposures.rules[]` | Repeated rule | `exposureCode`, `ageAtExposure`, `unit`, `value`, `date`, `duration` |
| `interventionsOrProcedures.rules[]` | Repeated rule | `procedureCode`, `ageAtProcedure`, `bodySite`, `dateOfProcedure` |
| `measures.rules[]` | Repeated rule | `assayCode`, quantity, reference range, procedure |
| `phenotypicFeatures.rules[]` | Repeated rule | `featureType` |
| `treatments.rules[]` | Repeated rule | `treatmentCode`, route, age, cumulative dose, dose interval |
| `info` | Field list | Selected project fields and optional age range |

Target property names use the camelCase spelling from the Beacon v2 schema.
The authoring form is compiled into a fully explicit internal mapping before
records are processed.

## Biosamples

`beacon.biosamples.rules[]` uses the same concise rule structure. Required
properties may be declared on each rule or inherited from
`beacon.biosamples.defaults`:

| Property | Purpose |
| --- | --- |
| `id` | Biosample identifier, commonly `{ from: sourceValue }` |
| `biosampleStatus` | Required ontology term |
| `sampleOriginType` | Required ontology term |
| `individualId` | Optional explicit link; defaults to the generated individual ID |

Optional properties are `sampleOriginDetail`, `collectionDate`, `notes`,
`obtentionProcedure`, `measurements`, and selected `info.sourceFields`.
Biosample measurements use the same structured measure rule as individual
measurements: `assayCode` identifies what was measured, while the quantity
contains the numeric value and unit.

The mapping is evaluated only when `biosamples` is requested with entity-aware
BFF output. Missing or empty biosample IDs do not produce placeholder records.

## Datasets And Cohorts

`beacon.datasets.defaults` and `beacon.cohorts.defaults` augment entities
synthesized from the converted individuals. They do not map one entity per
source row.

Dataset defaults can include `id`, `name`, `description`, `version`,
`externalUrl`, `createDateTime`, `updateDateTime`, and `info`. Cohort defaults
can include `id`, `name`, `description`, `cohortType`, `cohortDesign`,
`cohortDataTypes`, `inclusionCriteria`, `exclusionCriteria`, and `info`.

These overrides apply only to routes that read a mapping file. OMOP conversion
does not read this configuration.

## Validation And Provenance

Before conversion, Convert-Pheno:

1. Rejects duplicate YAML or JSON mapping keys
2. Validates the document against `share/schema/mapping.json`
3. Checks the mapping and Beacon schema versions
4. Checks that the route's normalized record profile matches `source.profile`
5. Checks referenced source fields against the input header

Generated BFF preserves the unmodified input row under `info.CSV_columns` or
`info.REDCap_columns` by default. Use `--no-source-info` to omit this copy.
Use `--search-audit-tsv FILE` to record ontology queries and their resolution.
