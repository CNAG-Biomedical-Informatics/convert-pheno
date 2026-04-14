# Convert-Pheno

`Convert-Pheno` is a toolkit for interconverting standard clinical and phenotypic data models

Supported formats include BFF, PXF, OMOP CDM, REDCap, CDISC-ODM and CSV

## Quick Start

Typical CLI usage:

```bash
convert-pheno -ipxf pxf.json -obff individuals.json
convert-pheno -ipxf pxf.json -obff --entities individuals biosamples datasets cohorts --out-dir out/
convert-pheno -ibff individuals.json -opxf phenopackets.json
convert-pheno -iomop dump.sql.gz -obff individuals.json.gz --stream --ohdsi-db
```

For backward compatibility, the legacy form `-iomop ... -obff` still emits Beacon `individuals` by default.

Internally, most conversions use `BFF` as the center model before continuing to other output formats when needed.

## Multi-Entity Output

BFF output can now be entity-aware through `--entities`.

Current support:

- `individuals` as the default BFF output entity
- `biosamples` as first-class BFF output for `-ipxf` when the input contains biosample data
- `datasets` and `cohorts` synthesized from the normalized `individuals` collection

Example:

```bash
convert-pheno -ipxf pxf.json -obff --entities individuals biosamples datasets cohorts --out-dir out/
```

This can write:

- `out/individuals.json`
- `out/biosamples.json`
- `out/datasets.json`
- `out/cohorts.json`

For mapping-file workflows such as `csv2bff`, `redcap2bff`, and `cdisc2bff`, synthesized `datasets` and `cohorts` can be customized through the top-level `beacon` section of the mapping file

## Mapping Files

Mapping-file based tabular conversions now use an entity-aware layout

- `project` keeps project-level metadata
- `beacon.individuals` contains the semantic mapping rules for Beacon `individuals`
- `beacon.datasets`, `beacon.cohorts`, and `beacon.biosamples` can provide metadata or defaults for emitted Beacon entities

This makes the mapping structure consistent with multi-entity BFF output while keeping `individuals` as the central normalized model

## Selected CLI Features

Useful recent options include:

- `--default-vital-status` to control the fallback `subject.vitalStatus.status` in `bff2pxf`
- `--search-audit-tsv` to write a TSV report of ontology lookup results for mapping-file conversions
- generic `-i/-o` syntax in addition to the format-specific shortcuts
- `--out-entity entity=file` to customize filenames in multi-entity BFF output

## Installation

Detailed installation instructions live in dedicated Markdown docs:

- [Non-containerized installation](non-containerized/README.md)
- [Containerized installation](docker/README.md)

Published documentation:

- <https://cnag-biomedical-informatics.github.io/convert-pheno>

## CLI Documentation

The CLI now keeps concise built-in help in `bin/convert-pheno`.

Long-form CLI documentation lives in Markdown:

- [CLI guide](docs/use-as-a-command-line-interface.md)
- [Download and installation](docs/download-and-installation.md)

## Examples

Repository fixtures under `t/` double as runnable examples.

Useful examples:

```bash
bin/convert-pheno -ipxf t/pxf2bff/in/pxf.json -obff individuals.json
bin/convert-pheno -ipxf t/pxf2bff/in/pxf_biosamples.json -obff --entities individuals biosamples datasets cohorts --out-dir out/
bin/convert-pheno -icsv t/csv2bff/in/csv_data.csv --mapping-file t/csv2bff/in/csv_mapping.yaml --search-audit-tsv search-audit.tsv -obff individuals.json
bin/convert-pheno -ibff t/bff2pxf/in/individuals.json -opxf phenopackets.json --default-vital-status UNKNOWN_STATUS
bin/convert-pheno -iomop t/omop2bff/in/omop_cdm_eunomia.sql -opxf phenopackets.json
bin/convert-pheno -iomop t/omop2bff/in/gz/omop_cdm_eunomia.sql.gz -obff individuals.json.gz --stream --omop-tables DRUG_EXPOSURE
```

## Citation

If you use `Convert-Pheno` in published work, please cite:

Rueda, M et al. (2024). *Convert-Pheno: A software toolkit for the interconversion of standard data models for phenotypic data*. Journal of Biomedical Informatics. <https://doi.org/10.1016/j.jbi.2023.104558>

## Author

Manuel Rueda, PhD. CNAG: <https://www.cnag.eu>
