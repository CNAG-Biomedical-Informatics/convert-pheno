# Convert-Pheno

`Convert-Pheno` is a toolkit for interconverting standard clinical and phenotypic data models.

It currently supports practical workflows around:

- BFF `individuals` JSON
- Phenopackets v2 (PXF)
- OMOP-CDM
- REDCap
- CDISC-ODM
- CSV
- flattened CSV / 1D JSON
- JSON-LD

## Quick Start

Typical CLI usage:

```bash
convert-pheno -ipxf pxf.json -obff individuals.json
convert-pheno -ibff individuals.json -opxf phenopackets.json
convert-pheno -iomop dump.sql.gz -obff individuals.json.gz --stream --ohdsi-db
```

For backward compatibility, the legacy form `-iomop ... -obff` still emits Beacon `individuals` by default.

Internally, most conversions use `BFF` as the center model before continuing to other output formats when needed.

## Multi-Entity Output

BFF output can now be entity-aware through `--entities`.

Current support:

- `individuals` as the legacy default
- `biosamples` for `-ipxf` when the input contains biosample data

Example:

```bash
convert-pheno -ipxf pxf.json --entities biosamples --out-dir out/
```

This writes:

- `out/biosamples.json`

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
bin/convert-pheno -ipxf t/pxf2bff/in/pxf_biosamples.json --entities biosamples --out-dir out/
bin/convert-pheno -iomop t/omop2bff/in/omop_cdm_eunomia.sql -opxf phenopackets.json
bin/convert-pheno -iomop t/omop2bff/in/gz/omop_cdm_eunomia.sql.gz -obff individuals.json.gz --stream --omop-tables DRUG_EXPOSURE
```

## Citation

If you use `Convert-Pheno` in published work, please cite:

Rueda, M et al. (2024). *Convert-Pheno: A software toolkit for the interconversion of standard data models for phenotypic data*. Journal of Biomedical Informatics. <https://doi.org/10.1016/j.jbi.2023.104558>

## Author

Manuel Rueda, PhD. CNAG: <https://www.cnag.eu>
