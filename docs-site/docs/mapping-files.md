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
  profiles: [redcap]

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
      source:
        fields: [record_id, redcap_event_name]
        primaryKey: record_id
      separator: ':'

    sex:
      source: { field: sex }
      target:
        query: { from: value }

    diseases:
      - source:
          field: diagnosis
          when: { nonEmpty: true }
        target:
          diseaseCode:
            query:
              from: value
              aliases:
                UC: Ulcerative Colitis
                CD: Crohn Disease
          ageOfOnset: { sourceField: age_at_diagnosis }

    info:
      source:
        fields: [record_id, redcap_event_name]
```

</details>

The top-level sections have distinct responsibilities:

| Section | Purpose |
| --- | --- |
| `source` | Declares which input routes may use the mapping |
| `target` | Declares the target model and Beacon schema version |
| `project` | Identifies and versions the project mapping |
| `defaults` | Sets the default ontology for term lookup |
| `records` | Defines visit and longitudinal baseline behavior |
| `beacon` | Contains entity-specific target mappings and defaults |

The route still determines how the source is parsed. For example,
`source.profiles: [redcap]` does not turn a CSV route into REDCap; it only
confirms that this mapping is intended for the selected route.

## Reading A Rule

Each rule separates the source condition from the target property:

```yaml
- source:
    field: diagnosis
    when: { nonEmpty: true }
  target:
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
| `query: { literal: Hemoglobin Measurement }` | Search a fixed label |
| `term: { id: 'NCIT:C...', label: ... }` | Use a known ontology term without a database search |

Use exact terms when the identifier is already curated. Otherwise, use a
query and review ontology resolution with `--search-audit-tsv`.

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
    mappings:
      - source:
          field: sample_id
          when: { nonEmpty: true }
        target:
          id: { from: sourceValue }
          individualId: { from: individualId }
          biosampleStatus:
            term: { id: 'NCIT:C126101', label: Not Available }
          sampleOriginType:
            query: { literal: Whole Blood }
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
