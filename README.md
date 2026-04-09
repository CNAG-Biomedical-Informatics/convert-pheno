<p align="left">
  <a href="https://github.com/cnag-biomedical-informatics/convert-pheno"><img src="https://raw.githubusercontent.com/cnag-biomedical-informatics/convert-pheno/main/docs/img/CP-logo.png" width="220" alt="Convert-Pheno"></a>
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
- [Installation](#installation)
  - [Non-Containerized](non-containerized/README.md)
  - [Containerized](docker/README.md)
- [How to run convert-pheno](#how-to-run-convert-pheno)
- [Citation](#citation)
  - [Author](#author)
- [License](#copyright-and-license)

# NAME

convert-pheno - A script to interconvert common data models for phenotypic data

# SYNOPSIS

    convert-pheno [-i input-type] <infile> [-o output-type] <outfile> [-options]

        Input arguments:
                -ibff                    Beacon v2 Models ('individuals' JSON|YAML) file
                -iomop                   OMOP-CDM CSV files or PostgreSQL dump
                -ipxf                    Phenopacket v2 (JSON|YAML) file
                -iredcap (experimental)  REDCap (raw data) export CSV file
                -icdisc  (experimental)  CDISC-ODM v1 XML file
                -icsv    (experimental)  Raw data CSV

                (Wish-list)
                #-iopenehr               openEHR

        Output arguments:
                -obff                    Beacon v2 Models ('individuals' JSON|YAML) file
                -opxf                    Phenopacket v2 (JSON|YAML) file
                -oomop   (experimental)  Prefix for OMOP-CDM tables (CSV)

                Compatible with -i(bff|pxf):
                -ocsv                    Flatten data to CSV
                -ojsonf                  Flatten data to 1D-JSON (or 1D-YAML if suffix is .yml|.yaml)
                -ojsonld (experimental)  JSON-LD (interoperable w/ RDF ecosystem; YAML-LD if suffix is .ymlld|.yamlld)

        Output behavior:
          -out-dir <directory>           Output (existing) directory
          -entities <list>               Comma-separated Beacon entities for BFF output [individuals]
                                         Current support: individuals (legacy default), biosamples from -ipxf when source data contains biosamples
                                         If multiple entities are requested, one file per entity is written under --out-dir
          -O                             Overwrite output file(s)

        Mapping / schema:
          -mapping-file <file>           Fields mapping YAML (or JSON) file
          -rcd|redcap-dictionary <file>  REDCap data dictionary CSV file
          -schema-file <file>            Alternative JSON Schema for mapping file
          -svs|self-validate-schema      Perform a self-validation of the JSON schema that defines mapping (requires IO::Socket::SSL)
          -phl|print-hidden-labels       Print original values (before DB mapping) of text fields <_labels>

        OMOP-specific:
          -exposures-file <file>         CSV file with a list of 'concept_id' considered to be exposures (with -iomop)
          -max-lines-sql <number>        Maximum lines read per table from SQL dump [500]
          -ohdsi-db                      Use Athena-OHDSI database (~2.2GB) with -iomop
          -omop-tables <tables>          OMOP-CDM tables to be processed. Tables <CONCEPT> and <PERSON> are always included.
          -path-to-ohdsi-db <directory>  Directory for the file <ohdsi.db>
          -stream                        Enable incremental processing with -iomop and legacy -obff output [>no-stream|stream]
          -sql2csv                       Print SQL TABLES (only valid with -iomop). Mutually exclusive with --stream

        Search / text matching:
          -search <type>                 Type of search [>exact|mixed|fuzzy]
          -text-similarity-method <method> The method used to compare values to DB [>cosine|dice]
          -min-text-similarity-score <score> Minimum score for cosine similarity (or Sorensen-Dice coefficient) [0.8] (to be used with --search [mixed|fuzzy])
          -levenshtein-weight <weight>   Set the normalized Levenshtein weight for fuzzy search composite scoring (default: 0.1, range: 0-1)

        Input / misc:
          -sep|separator <char>          Delimiter character for CSV files [;] e.g., --sep $'\t'
          -test                          Does not print time-changing-events (useful for file-based cmp)
          -u|username <username>         Set the username

        Generic Options:
          -debug <level>                 Print debugging level (from 1 to 5, being 5 max)
          -help                          Brief help message
          -log                           Save log file (JSON). If no argument is given then the log is named [convert-pheno-log.json]
          -man                           Full documentation
          -no-color                      Don't print colors to STDOUT [>color|no-color]
          -v|verbose                     Verbosity on
          -V|version                     Print Version

# DESCRIPTION

`convert-pheno` is a command-line front-end to the CPAN's module [Convert::Pheno](https://metacpan.org/pod/Convert%3A%3APheno).

For backward compatibility, the compact legacy form `-iomop ... -obff` still emits the Beacon
`individuals` entity by default. When using `--entities` with BFF output, the CLI can emit one
or more Beacon entity files under `--out-dir`. At the moment, non-legacy entity output is
available for `-ipxf` with `biosamples` when the input contains biosample data.

# SUMMARY

`convert-pheno` is a command-line front-end to the CPAN's module [Convert::Pheno](https://metacpan.org/pod/Convert%3A%3APheno) to interconvert common data models for phenotypic data.

# INSTALLATION

For day-to-day CLI use, install via CPAN or use the published Docker image.

For detailed installation workflows, see:

- General installation:

    [https://cnag-biomedical-informatics.github.io/convert-pheno/download-and-installation/](https://cnag-biomedical-informatics.github.io/convert-pheno/download-and-installation/)

- CLI usage:

    [https://cnag-biomedical-informatics.github.io/convert-pheno/use-as-a-command-line-interface/](https://cnag-biomedical-informatics.github.io/convert-pheno/use-as-a-command-line-interface/)

- Docker image:

    [https://hub.docker.com/r/manuelrueda/convert-pheno](https://hub.docker.com/r/manuelrueda/convert-pheno)

Minimal non-containerized install via CPAN:

    cpanm Convert::Pheno
    convert-pheno --help

# HOW TO RUN CONVERT-PHENO

For executing convert-pheno you will need:

- Input file(s):

    A text file in one of the accepted formats.

    Note that when using `--iomop`, I/O files can be gzipped.

- Optional: 

    Athena-OHDSI database

    The Athena-OHDSI database may be needed when using `-iomop`. See the OMOP and installation
    documentation for download details and placement options:

    [https://cnag-biomedical-informatics.github.io/convert-pheno/omop-cdm/](https://cnag-biomedical-informatics.github.io/convert-pheno/omop-cdm/)

    [https://cnag-biomedical-informatics.github.io/convert-pheno/download-and-installation/](https://cnag-biomedical-informatics.github.io/convert-pheno/download-and-installation/)

**Examples:**

Note that you can find input examples for all conversions within the `t/` directory of this repository:

    $ bin/convert-pheno -ipxf t/pxf2bff/in/pxf.json -obff individuals.json

    $ bin/convert-pheno -ipxf t/pxf2bff/in/pxf.json --entities biosamples --out-dir out/

    $ bin/convert-pheno -ibff t/bff2pxf/in/individuals.json -opxf phenopackets.yaml --out-dir my_out_dir 

    $ bin/convert-pheno -iomop t/omop2bff/in/omop_cdm_eunomia.sql -opxf phenopackets.json -max-lines-sql 2694

    $ bin/convert-pheno -ibff t/bff2omop/in/individuals.json -oomop my_prefix --ohdsi-db # Needs ohdsi.db

Generic examples:

    $ $path/convert-pheno -iredcap redcap.csv -opxf phenopackets.json --redcap-dictionary redcap_dict.csv --mapping-file mapping_file.yaml

    $ $path/convert-pheno -iomop dump.sql.gz -obff individuals.json.gz --stream -omop-tables measurement -verbose

    $ $path/convert-pheno -iomop dump.sql.gz -obff individuals.json.gz

    $ $path/convert-pheno -cdisc cdisc_odm.xml -obff individuals.json --rcd redcap_dict.csv --mapping-file mapping_file.yaml --search mixed --min-text-similarity-score 0.6

    $ $path/convert-pheno -iomop *csv -obff individuals.json -sep ','

    $ carton exec -- $path/convert-pheno -ibff individuals.json -opxf phenopackets.json # If using Carton

## COMMON ERRORS AND SOLUTIONS

    * Error message: CSV_XS ERROR: 2023 - EIQ - QUO character not allowed @ rec 1 pos 21 field 1
      Solution: Make sure you use the right character separator for your data with --sep <char>. 
                The script tries to guess it from the file extension, but sometimes extension and actual separator do not match. 
                When using REDCap as input, make sure that <--iredcap> and <--rcd> files use the same separator field.
                The defauly value for the separator is ';'. 
      Example for tab separator in CLI.
       --sep  $'\t' 

    * Error message: Error: malformed UTF-8 character in JSON string, at character offses...
      Solution:  iconv -f ISO-8859-1 -t UTF-8 yourfile.json -o yourfile-utf8.json

# CITATION

The author requests that any published work that utilizes `Convert-Pheno` includes a cite to the the following reference:

Rueda, M et al., (2024). Convert-Pheno: A software toolkit for the interconversion of standard data models for phenotypic data. Journal of Biomedical Informatics. [DOI](https://doi.org/10.1016/j.jbi.2023.104558)

# AUTHOR 

Written by Manuel Rueda, PhD. Info about CNAG can be found at [https://www.cnag.eu](https://www.cnag.eu).

# COPYRIGHT AND LICENSE

This PERL file is copyrighted. See the LICENSE file included in this distribution.
