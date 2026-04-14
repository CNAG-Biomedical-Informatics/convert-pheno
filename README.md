<p align="left">
  <a href="https://github.com/cnag-biomedical-informatics/convert-pheno"><img src="https://raw.githubusercontent.com/cnag-biomedical-informatics/convert-pheno/main/docs/img/CP-logo.png" width="180" alt="Convert-Pheno"></a>
  <a href="https://github.com/cnag-biomedical-informatics/convert-pheno"><img src="https://raw.githubusercontent.com/cnag-biomedical-informatics/convert-pheno/main/docs/img/CP-text.png" width="500" alt="Convert-Pheno"></a>
</p>
<p align="center">
    <em>A software toolkit for the interconversion of standard data models for phenotypic data</em>
</p>

[![Build and Test](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/build-and-test.yml/badge.svg)](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/build-and-test.yml)
[![Coverage Status](https://coveralls.io/repos/github/CNAG-Biomedical-Informatics/convert-pheno/badge.svg?branch=main)](https://coveralls.io/github/CNAG-Biomedical-Informatics/convert-pheno?branch=main)
[![CPAN Publish](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/cpan-publish.yml/badge.svg)](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/cpan-publish.yml)
[![Kwalitee Score](https://cpants.cpanauthors.org/dist/Convert-Pheno.svg)](https://cpants.cpanauthors.org/dist/Convert-Pheno)
![version](https://img.shields.io/badge/version-0.29_beta-orange)
[![Docker Build](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/docker-build-multi-arch.yml/badge.svg)](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/docker-build-multi-arch.yml)
[![Docker Pulls](https://badgen.net/docker/pulls/manuelrueda/convert-pheno?icon=docker&label=pulls)](https://hub.docker.com/r/manuelrueda/convert-pheno/)
[![Docker Image Size](https://img.shields.io/docker/image-size/manuelrueda/convert-pheno/latest?logo=docker&label=image%20size)](https://hub.docker.com/r/manuelrueda/convert-pheno/)
[![Documentation Status](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/documentation.yml/badge.svg)](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/documentation.yml)
[![License](https://img.shields.io/badge/License-Artistic%202.0-0298c3.svg)](https://opensource.org/licenses/Artistic-2.0)
[![Google Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/drive/1T6F3bLwfZyiYKD6fl1CIxs9vG068RHQ6?usp=sharing)

---

**📘 Documentation:** <a href="https://cnag-biomedical-informatics.github.io/convert-pheno" target="_blank">https://cnag-biomedical-informatics.github.io/convert-pheno</a>

**📓 Google Colab tutorial:** <a href="https://colab.research.google.com/drive/1T6F3bLwfZyiYKD6fl1CIxs9vG068RHQ6?usp=sharing" target="_blank">https://colab.research.google.com/drive/1T6F3bLwfZyiYKD6fl1CIxs9vG068RHQ6?usp=sharing</a>

**📦 CPAN Distribution:** <a href="https://metacpan.org/pod/Convert::Pheno" target="_blank">https://metacpan.org/pod/Convert::Pheno</a>

**🐳 Docker Hub Image:** <a href="https://hub.docker.com/r/manuelrueda/convert-pheno/tags" target="_blank">https://hub.docker.com/r/manuelrueda/convert-pheno/tags</a>

**🌐 Web App UI:** <a href="https://convert-pheno.cnag.cat" target="_blank">https://convert-pheno.cnag.cat</a>

---

# Table of contents
- [Description](#description)
  - [Name](#name)
  - [Synopsis](#synopsis)
  - [Summary](#summary)
- [README](README.source.md)

# Convert-Pheno

`Convert-Pheno` is a toolkit for interconverting standard clinical and phenotypic data models.

It currently supports practical workflows around:

- BFF entity bundles centered on `individuals`
- first-class BFF `biosamples` output from `PXF`
- synthesized BFF `datasets` and `cohorts`
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
convert-pheno -ipxf pxf.json --entities individuals biosamples datasets cohorts --out-dir out/
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
convert-pheno -ipxf pxf.json --entities individuals biosamples datasets cohorts --out-dir out/
```

This can write:

- `out/individuals.json`
- `out/biosamples.json`
- `out/datasets.json`
- `out/cohorts.json`

For mapping-file workflows such as `csv2bff`, `redcap2bff`, and `cdisc2bff`, synthesized `datasets` and `cohorts` can be customized through the top-level `beacon` section of the mapping file.

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
bin/convert-pheno -ipxf t/pxf2bff/in/pxf_biosamples.json --entities individuals biosamples datasets cohorts --out-dir out/
bin/convert-pheno -iomop t/omop2bff/in/omop_cdm_eunomia.sql -opxf phenopackets.json
bin/convert-pheno -iomop t/omop2bff/in/gz/omop_cdm_eunomia.sql.gz -obff individuals.json.gz --stream --omop-tables DRUG_EXPOSURE
```

## Citation

If you use `Convert-Pheno` in published work, please cite:

Rueda, M et al. (2024). *Convert-Pheno: A software toolkit for the interconversion of standard data models for phenotypic data*. Journal of Biomedical Informatics. <https://doi.org/10.1016/j.jbi.2023.104558>

## Author

Manuel Rueda, PhD. CNAG: <https://www.cnag.eu>
