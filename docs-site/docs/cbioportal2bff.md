---
title: cBioPortal to BFF
sidebar_label: cBioPortal to BFF
---

The built-in clinical study mapping is summarized below. An optional Mapping V2
file can add project-specific patient and sample columns.

| cBioPortal source | BFF destination | Behavior |
| --- | --- | --- |
| Study identifier | Dataset identifier | Preserved as the stable dataset identity |
| Study name and description | Dataset name and description | Copied from study metadata |
| Patient identifier | Individual identifier | Required and not rewritable by the optional mapping |
| Patient sex or gender | Individual sex | Common male, female, other, and unknown values are normalized |
| Patient survival status | Phenopackets vital-status provenance | Living/alive and deceased values are recognized when present |
| OncoTree code and cancer labels | Individual disease | One distinct disease term is emitted per patient |
| Sample identifier | Biosample identifier | Required and not rewritable by the optional mapping |
| Sample patient identifier | Biosample individual link | Must resolve to a known patient |
| OncoTree code and detailed cancer label | Biosample histological diagnosis | Emitted as an `OncoTree:` term |
| Sample type | Source provenance | Preserved exactly; not assumed to be an ontology concept |
| Case-list stable identifier and name | Cohort identifier and name | Preserved from each case-list descriptor |
| Case-list sample members | Cohort membership and size | Samples are resolved to distinct patient identifiers |

## Required Defaults

BFF requires ontology terms for `biosampleStatus` and `sampleOriginType`.
cBioPortal clinical tables do not guarantee ontology identifiers for either
field, so the built-in mapping uses `NCIT:C126101` (`Not Available`). An
optional mapping may replace these defaults with curated terms.

The source value `SAMPLE_TYPE=Primary` is not mapped to the generic NCIT term
whose label is also “Primary.” Label equality alone does not establish that a
source category represents specimen origin.

## Source Provenance

With the default `--source-info`, generated records retain:

- patient attributes under `info.cbioportal.patient`
- sample attributes under `info.cbioportal.sample`
- study and attribute-definition metadata under dataset `info.cbioportal`
- case-list descriptors and resolved membership under cohort `info.cbioportal`

`--no-source-info` removes copied source payloads. Resolved cohort membership
is retained because it is part of the converted relationship graph.

## Optional Mapping

Use `source.profile: cbioportal`. Individual rules read patient columns and
biosample rules read sample columns. Dataset and cohort defaults can augment
the source-derived collection metadata. The package identifiers remain
authoritative so references cannot be broken by configuration.

See the [cBioPortal format guide](cbioportal) for commands and input scope.
