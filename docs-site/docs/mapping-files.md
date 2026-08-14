---
id: mapping-files
title: Mapping Files
sidebar_label: Mapping Files
slug: /mapping-files
---

Mapping files describe how project-specific `CSV`, `REDCap`, or `CDISC-ODM`
fields become Beacon v2 records. They can also augment the built-in cBioPortal
mapping or define reviewed terminology decisions for SDTM Dataset-JSON and
Dataset-XML. This page explains the Mapping V2 contract through a REDCap
example and identifies the parts that differ for other source profiles.

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

CSV needs only the source file and mapping. REDCap-origin ODM uses the same
`redcap` mapping profile and dictionary as REDCap CSV. Standard or OpenClinica
ODM uses `source.profile: cdisc-odm` and resolves labels, data types, and coded
values from metadata embedded in the XML, without a REDCap dictionary.

cBioPortal uses `source.profile: cbioportal`. Its package metadata already
defines patients, samples, study identity, and case-list links, so a mapping is
optional and is used only for additional project-specific clinical columns.

Dataset-JSON and Dataset-XML use `source.profile: sdtm`. Their structural SDTM
mapping is built in, so the optional mapping contains only terminology rules.
Dataset-XML still requires Define-XML independently of this optional mapping.

## Recipe: CSV To Validated BFF

::::tip[A small end-to-end example]
Suppose a project gives you this semicolon-delimited `clinical.csv`:

```csv
participant_id;sex;diagnosis
P001;Female;ASTHMA_LOCAL
P002;Male;
```

The values are deliberately simple, but the important detail is realistic:
`ASTHMA_LOCAL` is a project label, not an ontology term. A first Mapping V2 file
can translate that label while asking Convert-Pheno to find the actual NCIT
concept:

```yaml title="mapping.yaml"
mappingVersion: 2

source:
  profile: csv

target:
  model: beacon
  schemaVersion: '2.0.0'

project:
  id: csv-bff-recipe
  version: '1.0'

defaults:
  ontology: ncit

records: {}

beacon:
  individuals:
    id:
      sourceFields: [participant_id]
      primaryKey: participant_id
      missingValue: NA

    sex:
      sourceField: sex
      query: {from: value}

    diseases:
      rules:
        - sourceField: diagnosis
          when: {nonEmpty: true}
          diseaseCode:
            query:
              from: value
              aliases:
                ASTHMA_LOCAL: Asthma
```

Now convert the CSV and ask for a terminology audit in the same run:

```bash
mkdir -p output

convert-pheno \
  -icsv clinical.csv \
  --separator ';' \
  --mapping-file mapping.yaml \
  --search exact \
  --term-audit output/terminology.tsv \
  -obff output/individuals.json
```

`individuals.json` is the BFF result. `terminology.tsv` explains how each
ontology decision was made. In this example, Female, Male, and Asthma should be
exact database matches. If a term is unresolved, correct the alias or mapping
and run the command again; do not lower the search threshold merely to obtain a
result.

::::

<details>
<summary>Advanced: tool-assisted terminology validation</summary>

A tool-enabled LLM can carry out most of this workflow. Give it access to the
source schema and distinct values, the Mapping V2 documentation, the ontology
databases, Convert-Pheno, the terminology audit, and the target validator. It
can then draft the mapping, run it, inspect the evidence, and revise it instead
of guessing terms from memory.

For example, when the LLM proposes a direct NCIT term, it can verify the pair
against the database bundle selected by `share/db/manifest.json`:

```bash
sqlite3 share/db/v0/ncit.db \
  "SELECT 'NCIT:' || id, label FROM NCIT_table WHERE id = 'C28397' COLLATE NOCASE;"
```

Record which ontology release you checked. Its version and checksum are in
`share/db/manifest.json`.

Then answer two separate questions:

- **Does the code exist, and does its label match?** Check the ontology database.
- **Does it mean the same thing as the source value?** Check the source
  documentation and ask a domain expert when the meaning is unclear.

If the audit says `configured` or `direct_mapping`, Convert-Pheno copied a term
provided by the mapping file. The LLM should perform the database check as a
separate tool call and record the result.

Finally, validate the generated BFF with
[`bff-tools`](https://github.com/CNAG-Biomedical-Informatics/beacon2-cbi-tools):

```bash
bff-tools validate -i output/individuals.json -nc -ne
```

Review every reported path. With some Beacon v2 schema releases, a disease may
produce an `ageOfOnset` `oneOf` message because the schema's object alternatives
overlap. That specific message is a known schema ambiguity, not evidence of an
incorrect ontology lookup. Retain it in the validation record, but do not use
it to dismiss any other validation issue.

This inspect, map, convert, audit, validate, and revise cycle can be largely
automated by an LLM with the right tools. People still decide genuinely
ambiguous clinical meanings and approve the final mapping. For restricted data,
run the workflow in an approved environment and expose only the information the
model needs.

</details>

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

| Section | Required for | Purpose |
| --- | --- | --- |
| `source` | All profiles | Declares the normalized source profile |
| `target` | All profiles | Declares the target model and Beacon schema version |
| `project` | All profiles | Identifies and versions the project mapping |
| `defaults` | All profiles | Sets the default ontology for term lookup |
| `records` | Tabular profiles | Defines visit and longitudinal baseline behavior |
| `beacon` | Tabular profiles | Contains entity-specific target rules |
| `terminology` | `sdtm` | Contains `DOMAIN.FIELD` terminology rules |

Supported default ontologies are `ncit`, `icd10`, `ohdsi`, `cdisc`, `omim`,
and `hpo`. Individual term rules may select another supported ontology.

The route still determines how the input is parsed. `source.profile` describes
the record and metadata contract consumed by the mapping:

| Profile | Use |
| --- | --- |
| `csv` | CSV input |
| `redcap` | REDCap CSV or a REDCap-origin ODM export with an external dictionary |
| `cdisc-odm` | Standard or vendor ODM with embedded `MetaDataVersion`, `ItemDef`, and `CodeList` metadata |
| `cbioportal` | cBioPortal patient and sample clinical tables discovered from a study package |
| `sdtm` | Dataset-JSON or Dataset-XML terminology enrichment; structural mapping remains built in |

ODM mappings use stable `ItemOID` values as source fields. A REDCap ODM export
can reuse its corresponding REDCap mapping. Other ODM documents need rules
tailored to their own item identifiers, but do not need a fabricated REDCap
dictionary when the required metadata is embedded.

## Compact SDTM Terminology Mapping

For Dataset-JSON and Dataset-XML, omit `records` and `beacon`. Key each
terminology decision by the SDTM domain and variable:

```yaml
mappingVersion: 2
source: { profile: sdtm }
target: { model: beacon, schemaVersion: '2.0.0' }
project: { id: my_study, version: '1.0' }
defaults: { ontology: ncit }

terminology:
  AE.AESEV:
    query:
      from: value
      aliases:
        MILD_GRADE: Mild
  MH.MHDECOD:
    terms:
      Asthma: { id: 'NCIT:C28397', label: Asthma }
```

The alias key is the source value; its value is the reviewed database label.
Aliases are selective: this example translates `MILD_GRADE`, while an unlisted
value such as `SEVERE` is queried unchanged. Case-only aliases are unnecessary
because lookup is case-insensitive. `terms` bypasses lookup for known values.
Define-XML `nci:ExtCodeID` identifiers take precedence over a label query and
are looked up exactly to obtain the canonical NCIT display. See
[Terminology Search](terminology-search) for the full precedence and audit fields.

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

Source selectors can make that behavior explicit:

| Key | Meaning |
| --- | --- |
| `sourceField` | Source column or ODM `ItemOID` evaluated by the rule |
| `optional` | Allows the field to be absent from compatible exports |
| `when.nonEmpty` | Requires a non-empty value |
| `when.values` | Accepts only the listed values |
| `when.notValues` | Rejects the listed values |

Repeated ODM item groups are evaluated occurrence by occurrence. Companion
`sourceField` values are taken from the same occurrence; ambiguous repeated
values in scalar sections are rejected rather than flattened.

Ontology queries can come from different places:

| Form | Use |
| --- | --- |
| `query: { from: value }` | Search using the recorded value |
| `query: { from: field }` | Search using the source column name |
| `query: { from: fieldNote }` | Search using the REDCap dictionary field note |
| `query: Hemoglobin Measurement` | Search a fixed label |
| `term: { id: 'NCIT:C...', label: ... }` | Use a known ontology term without a database search |
| `terms` | Select reviewed terms by source value without a database search |

The location of `from` changes its meaning. Inside `query`, it selects the text
used for ontology lookup. A direct value mapping such as
`id: { from: sourceValue }` copies a scalar value and does not query an
ontology database.

Use exact terms when the identifier is already curated. Otherwise, use a
query and review terminology resolution with `--term-audit`.

Scalar targets do not perform terminology lookup:

| Form | Result |
| --- | --- |
| `{ from: sourceValue }` | Uses the current rule value |
| `{ from: individualId }` | Uses the generated BFF individual ID |
| `{ sourceField: age }` | Uses another named source field |
| `{ literal: value }` | Uses a fixed string, number, or boolean |

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
continues to reflect the input file. Generic ODM uses the occurrence-aware
`info.CDISC_ODM` block instead.

## Other Beacon Entities

The individual mapping supports scalar demographic terms plus repeated
`diseases`, `exposures`, `interventionsOrProcedures`, `measures`,
`phenotypicFeatures`, and `treatments` rules. Target property names follow the
Beacon v2 camelCase schema.

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

## Validation And Provenance

Before conversion, Convert-Pheno rejects duplicate keys, validates the mapping
against `share/schema/mapping-v2.json`, checks mapping and Beacon versions, and
verifies the selected source profile and referenced fields.

Generated BFF retains source content under its format-specific `info` block by
default. Use `--no-source-info` to omit that copy and `--term-audit FILE`
to record direct terms, identifier lookups, label searches, and fallbacks.

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

For standard or OpenClinica ODM with embedded metadata, select the ODM profile
and omit the REDCap dictionary:

```bash
convert-pheno -icdisc-odm study.xml \
  --mapping-file odm-mapping.yaml \
  -obff individuals.json
```

For terminology review, add `--term-audit terminology.tsv`. Exact search
is the default; similarity modes and audit columns are documented under
[Terminology Search](terminology-search).

Continue with [REDCap](redcap), [CSV](csv), [Dataset-JSON](dataset-json), or
[Dataset-XML](dataset-xml).
