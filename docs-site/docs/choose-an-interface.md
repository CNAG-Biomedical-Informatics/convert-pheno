---
title: Ways to Run Convert-Pheno
sidebar_label: Ways to Run It
---

import Link from '@docusaurus/Link';

<div className="convertDocHero">
  <p className="convertEyebrow">How to run it</p>
  <h2>Choose the entry point by the shape of your input data.</h2>
  <p>
    The command-line interface is the main entry point. Use the API or module
    only when you are writing code that needs to call Convert-Pheno directly.
  </p>
  <div className="convertHeroActions">
    <Link className="button button--primary" to="/use-as-a-command-line-interface">CLI</Link>
    <Link className="button button--secondary" to="/use-as-an-api">API</Link>
    <Link className="button button--secondary" to="/use-as-a-module">Module</Link>
  </div>
</div>

| Entry point | Best for | Avoid when |
|-----------|----------|------------|
| [Command-Line Interface](use-as-a-command-line-interface) | Normal use: real files, mapping files, OMOP tables, REDCap exports, CDISC-ODM XML, audit logs, multi-entity BFF output | You are building a service that must call Convert-Pheno over HTTP(s) |
| [API](use-as-an-api) | Developer use: self-contained JSON payloads from applications, notebooks, or JavaScript clients | The conversion needs several local files, mapping files, or large OMOP exports |
| [Module](use-as-a-module) | Developer use: Perl/Python code that runs in the same environment as Convert-Pheno | You need a language-agnostic network contract |
| [Web App UI](https://cnag-biomedical-informatics.github.io/convert-pheno-ui/) | Display and exploration only; it currently uses an older Convert-Pheno version | You need reproducible batch processing or current v0.31 behavior |

## Practical Rule

- Use the **CLI** when your input is a file on disk.
- Use the **CLI** when the conversion needs `--mapping-file`, `--redcap-dictionary`, `--search-audit-tsv`, `--ohdsi-db`, or `--out-dir`.
- Use the **API** only when your input and output can be represented as one JSON request and response.
- Use the **Module** only when you are embedding Convert-Pheno in local Perl or Python code.

:::info[Mapping-file conversions]
Mapping-file augmentation for `datasets`, `cohorts`, and `biosamples` is available only in conversions that actually read a mapping file, such as `CSV`, `REDCap`, and `CDISC-ODM`.

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
