---
title: Which Interface Should I Use?
sidebar_label: Which Interface?
---

# Which Interface Should I Use?

Most users should start with the **command-line interface**. It exposes the full feature set and is the safest choice for file-based workflows.

| Interface | Best For | Avoid When |
|-----------|----------|------------|
| [Command-Line Interface](use-as-a-command-line-interface) | Real files, mapping files, OMOP tables, REDCap exports, CDISC-ODM XML, audit logs, multi-entity BFF output | You need to call Convert-Pheno inside a web service |
| [API](use-as-an-api) | Self-contained JSON payloads from applications, notebooks, or JavaScript clients | The conversion needs several local files, mapping files, or large OMOP exports |
| [Module](use-as-a-module) | Perl/Python code that runs in the same environment as Convert-Pheno | You need a language-agnostic network contract |
| [Web App UI](https://cnag-biomedical-informatics.github.io/convert-pheno-ui/) | Interactive exploration and smaller manual conversions | You need reproducible batch processing |

## Practical Rule

- Use the **CLI** when your input is a file on disk.
- Use the **CLI** when the conversion needs `--mapping-file`, `--redcap-dictionary`, `--search-audit-tsv`, `--ohdsi-db`, or `--out-dir`.
- Use the **API** when your input and output can be represented as one JSON request and response.
- Use the **Module** when you are embedding Convert-Pheno in local Perl or Python code.

:::info[Mapping-file workflows]
Mapping-file augmentation for `datasets`, `cohorts`, and `biosamples` is available only in conversions that actually read a mapping file, such as `CSV`, `REDCap`, and `CDISC-ODM` workflows.

`OMOP-CDM` conversion does not use the mapping file, so dataset and cohort metadata must come from the source data, defaults, or command-line options.
:::

## Output Choice

| Goal | Typical Output |
|------|----------------|
| Beacon-compatible clinical records | `-obff` |
| Phenopackets v2 exchange | `-opxf` |
| OMOP-CDM CSV tables | `-oomop --out-dir out/` |
| Flattened inspection files | `-ocsv`, `-ojsonf`, or `-ojsonld` |

For concrete commands, see [Conversion Recipes](conversion-recipes).
