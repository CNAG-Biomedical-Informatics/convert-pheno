---
id: mapping-files
title: Working with Mapping Files
sidebar_label: Mapping Files
slug: /mapping-files
---

Mapping files describe how project-specific `CSV`, `REDCap`, or `CDISC-ODM`
fields become Beacon v2 records. This page follows a REDCap example; the full
key reference is under [Mapping File](tbl/mapping-file).

:::tip[Google Colab version]
A runnable notebook is available in [Google Colab](https://colab.research.google.com/drive/1T6F3bLwfZyiYKD6fl1CIxs9vG068RHQ6), with a local copy in the [repository](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/nb/convert_pheno_cli_tutorial.ipynb).

The notebook clones the latest `main` branch and reports the Convert-Pheno
version and Git commit used.
:::

## Files Required

A REDCap conversion normally uses:

1. The data export in CSV format
2. The REDCap data dictionary in CSV format
3. A Convert-Pheno mapping file in YAML or JSON format

The data dictionary explains REDCap field types, labels, choices, notes, and
ranges. The mapping file makes the project-specific semantic decisions.

## Mapping V2 At A Glance

Two independent versions are declared at the top of every mapping:

| Key | Meaning |
| --- | --- |
| `mappingVersion: 2` | Version of the Convert-Pheno mapping language |
| `target.schemaVersion: '2.0.0'` | Beacon v2 schema version targeted by the mapping |
| `project.version` | Version assigned by your project to this mapping |

:::warning[Breaking mapping format]
Mapping V2 is intentionally not compatible with the pre-V2 layout. Removed
constructs such as `fieldTermLabels`, `valueTermLabels`, `targetFields`, and
`baselineFieldsToPropagate` are not accepted. This prevents old configuration
from being interpreted with new semantics.
:::

<details>
<summary>Compact REDCap mapping</summary>

```yaml
mappingVersion: 2

source:
  profile: redcap

target:
  model: beacon
  schemaVersion: '2.0.0'

project:
  id: my_study
  version: '1.0'

defaults:
  ontology: ncit

records:
  visitId:
    sourceField: redcap_event_name
  baseline:
    strategy: firstNonNull
    sourceFields: [sex, diagnosis]

beacon:
  individuals:
    id:
      sourceFields: [record_id, redcap_event_name]
      primaryKey: record_id
      separator: ':'

    sex:
      sourceField: sex
      query: { from: value }

    diseases:
      rules:
        - sourceField: diagnosis
          when: { nonEmpty: true }
          diseaseCode:
            query:
              from: value
              aliases:
                UC: Ulcerative Colitis
                CD: Crohn Disease
          ageOfOnset: { sourceField: age_at_diagnosis }

    info:
      sourceFields: [record_id, redcap_event_name]
```

</details>

The top-level sections have distinct responsibilities:

| Section | Purpose |
| --- | --- |
| `source` | Declares the normalized tabular profile consumed by the mapping |
| `target` | Declares the target model and Beacon schema version |
| `project` | Identifies and versions the project mapping |
| `defaults` | Sets the default ontology for term lookup |
| `records` | Defines visit and longitudinal baseline behavior |
| `beacon` | Contains entity-specific target mappings and defaults |

The route still determines how the input is parsed. `source.profile` describes
the normalized records consumed by the mapping, not the original file format.
Use `csv` for CSV records and `redcap` for REDCap records. CDISC-ODM input is
normalized into REDCap-shaped records, so REDCap and CDISC-ODM deliberately
share `source.profile: redcap` without duplicating the mapping.

## Reading A Rule

Each repeated section contains ordered rules. A rule keeps its source selector
and Beacon target properties together:

```yaml
diseases:
  rules:
    - sourceField: diagnosis
      when: { nonEmpty: true }
      diseaseCode:
        query:
          from: value
          aliases:
            UC: Ulcerative Colitis
```

Here, `diagnosis` is the source column. Empty cells are skipped. The recorded
value is used as the ontology query, after applying the optional alias.

Ontology queries can come from different places:

| Form | Use |
| --- | --- |
| `query: { from: value }` | Search using the recorded value |
| `query: { from: field }` | Search using the source column name |
| `query: { from: fieldNote }` | Search using the REDCap dictionary field note |
| `query: Hemoglobin Measurement` | Search a fixed label |
| `term: { id: 'NCIT:C...', label: ... }` | Use a known ontology term without a database search |

The location of `from` changes its meaning. Inside `query`, it selects the text
used for ontology lookup. A direct value mapping such as
`id: { from: sourceValue }` copies a scalar value and does not query an
ontology database.

Use exact terms when the identifier is already curated. Otherwise, use a
query and review ontology resolution with `--search-audit-tsv`.

## How Defaults Are Reused

`defaults` has a specific scope according to where it appears:

| Location | Applies to |
| --- | --- |
| Top-level `defaults.ontology` | Ontology queries that do not select another ontology |
| `beacon.individuals.<section>.defaults` | Every rule in that repeated individual section only |
| `beacon.biosamples.defaults` | Every rule under `beacon.biosamples.rules` |
| `beacon.datasets.defaults` and `beacon.cohorts.defaults` | Metadata for the synthesized entity, not rule inheritance |

A collection default is not an output record. Before conversion,
Convert-Pheno copies it into each sibling rule and then applies the values
written on that rule. This lets each rule declare only what differs:

```yaml
treatments:
  defaults:
    routeOfAdministration: { query: Oral Route of Administration }
    doseIntervals:
      quantity:
        unit: { query: Milligram }
  rules:
    - sourceField: aspirin_status
      treatmentCode: { query: aspirin }
      doseIntervals:
        quantity:
          value: { sourceField: aspirin_dose }
    - sourceField: infliximab_status
      treatmentCode: { query: infliximab }
      routeOfAdministration: { query: Intravenous Route of Administration }
      doseIntervals:
        quantity:
          value: { sourceField: infliximab_dose }
```

Both rules inherit `Milligram`. The aspirin rule also inherits the oral route;
the infliximab rule replaces only that route with the intravenous route.

The merge is recursive: rule values override matching defaults, while
unmentioned defaults remain in place. Arrays are replaced rather than joined,
and setting an optional property to `null` removes its inherited value.
Defaults apply only to target properties and only within their section;
`sourceField`, `optional`, and `when` always remain visible on each rule.

## Longitudinal Values

`records.baseline` can make a value recorded only at baseline available to
later rows for the same `primaryKey`:

```yaml
records:
  baseline:
    strategy: firstNonNull
    sourceFields: [sex, diagnosis]
```

Rows must be ordered so the first non-empty value appears before rows that need
it. Propagation affects target mapping only. The raw row preserved under
`info.REDCap_columns` or `info.CSV_columns` remains unchanged, so provenance
continues to reflect the input file.

## Other Beacon Entities

`beacon.biosamples` contains executable mapping rules, not just metadata. A
biosample is emitted when its source condition matches and an ID is available:

```yaml
beacon:
  biosamples:
    defaults:
      id: { from: sourceValue }
      individualId: { from: individualId }
      biosampleStatus:
        term: { id: 'NCIT:C126101', label: Not Available }
    rules:
      - sourceField: sample_id
        when: { nonEmpty: true }
        sampleOriginType: { query: Whole Blood }
        collectionDate: { sourceField: collection_date }
```

Rules can also populate `sampleOriginDetail`, `obtentionProcedure`, `notes`,
`measurements`, and selected `info` fields. Request `biosamples` explicitly in
entity-aware BFF output.

`beacon.datasets.defaults` and `beacon.cohorts.defaults` provide metadata for
entities synthesized from the converted individuals. These defaults are used
only by mapping-file routes.

## Run And Review

Convert REDCap directly to Phenopackets:

```bash
convert-pheno -iredcap redcap.csv \
  --redcap-dictionary dictionary.csv \
  --mapping-file mapping.yaml \
  -opxf phenopackets.json
```

Write individuals and mapped biosamples as separate BFF files:

```bash
convert-pheno -iredcap redcap.csv \
  --redcap-dictionary dictionary.csv \
  --mapping-file mapping.yaml \
  -obff \
  --entities individuals biosamples \
  --out-dir bff-output/
```

For ontology review, add `--search-audit-tsv mapping-audit.tsv`. Exact search
is the default; similarity modes and audit columns are documented under
[Database Search](tbl/db-search).

Continue with [REDCap](redcap), [CSV](csv), or the complete
[Mapping File](tbl/mapping-file) reference.
