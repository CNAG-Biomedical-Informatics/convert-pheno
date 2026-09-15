<p align="left">
  <a href="https://github.com/cnag-biomedical-informatics/convert-pheno"><img src="https://raw.githubusercontent.com/cnag-biomedical-informatics/convert-pheno/main/docs-site/static/img/CP-logo.png" width="180" alt="Convert-Pheno"></a>
  <a href="https://github.com/cnag-biomedical-informatics/convert-pheno"><img src="https://raw.githubusercontent.com/cnag-biomedical-informatics/convert-pheno/main/docs-site/static/img/CP-text.png" width="500" alt="Convert-Pheno"></a>
</p>
<p align="center">
    <em>A software toolkit for the interconversion of standard data models for phenotypic data</em>
</p>

[![Build and Test](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/build-and-test.yml/badge.svg)](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/build-and-test.yml)
[![Coverage Status](https://coveralls.io/repos/github/CNAG-Biomedical-Informatics/convert-pheno/badge.svg?branch=main)](https://coveralls.io/github/CNAG-Biomedical-Informatics/convert-pheno?branch=main)
[![CPAN Publish](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/cpan-publish.yml/badge.svg)](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/cpan-publish.yml)
![version](https://img.shields.io/badge/version-0.34-blue)
[![Docker Build](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/docker-build-multi-arch.yml/badge.svg)](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/docker-build-multi-arch.yml)
[![Docker Pulls](https://badgen.net/docker/pulls/manuelrueda/convert-pheno?icon=docker&label=pulls)](https://hub.docker.com/r/manuelrueda/convert-pheno/)
[![Documentation Status](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/documentation.yml/badge.svg)](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/documentation.yml)
[![License](https://img.shields.io/badge/License-Artistic%202.0-0298c3.svg)](https://opensource.org/licenses/Artistic-2.0)

---

[📘 Documentation](https://cnag-biomedical-informatics.github.io/convert-pheno) ·
[💻 Installation](https://cnag-biomedical-informatics.github.io/convert-pheno/download-and-installation) ·
[📓 Google Colab](https://colab.research.google.com/drive/1T6F3bLwfZyiYKD6fl1CIxs9vG068RHQ6?usp=sharing) ·
[📦 CPAN](https://metacpan.org/pod/Convert::Pheno) ·
[🐳 Docker](https://hub.docker.com/r/manuelrueda/convert-pheno/tags)

# Convert-Pheno

`Convert-Pheno` converts clinical and phenotypic records between BFF,
Phenopackets (PXF), OMOP-CDM, REDCap, CSV, CDISC formats, FHIR R4, openEHR,
cBioPortal, i2b2, PCORnet CDM, and Sentinel CDM.

The command-line interface is the primary interface. The same conversion engine
is also available through a Perl module, Python binding, HTTP(s) API, and native
desktop application.

## Quick Start

```bash
convert-pheno -ipxf phenopacket.json -obff individuals.json
convert-pheno -ibff individuals.json -opxf phenopackets.json
convert-pheno -iomop omop-export/ -obff individuals.json --ohdsi-db
```

Entity-aware BFF output can write individuals, biosamples, datasets, and
cohorts when the selected source route supports them:

```bash
convert-pheno -ipxf phenopacket.json \
  -obff --entities individuals biosamples datasets cohorts \
  --out-dir bff_out/
```

See [Choose a Conversion](https://cnag-biomedical-informatics.github.io/convert-pheno/choose-a-conversion)
for commands by source and target, or run `convert-pheno --help` for the full
CLI option list.

## Installation

- [Non-containerized installation](non-containerized/README.md)
- [Docker installation](docker/README.md)

## Desktop Application

From Convert-Pheno 0.35, a native desktop application provides route selection,
local file handling, conversion runs, output previews, and terminology review.
See the [desktop application guide](https://cnag-biomedical-informatics.github.io/convert-pheno/graphical-interface).

## Tested Examples

Synthetic fixtures under [`t/`](t/README.md) provide tested inputs and reference
outputs for the supported conversion routes.

## Citation

Rueda, M et al. (2024). *Convert-Pheno: A software toolkit for the
interconversion of standard data models for phenotypic data*. Journal of
Biomedical Informatics. <https://doi.org/10.1016/j.jbi.2023.104558>

## Author

Manuel Rueda, PhD. CNAG: <https://www.cnag.eu>
