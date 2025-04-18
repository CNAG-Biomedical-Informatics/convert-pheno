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
![version](https://img.shields.io/badge/version-0.28_beta-orange)
[![Docker Build](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/docker-build-multi-arch.yml/badge.svg)](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/docker-build-multi-arch.yml)
[![Docker Pulls](https://badgen.net/docker/pulls/manuelrueda/convert-pheno?icon=docker&label=pulls)](https://hub.docker.com/r/manuelrueda/convert-pheno/)
[![Docker Image Size](https://badgen.net/docker/size/manuelrueda/convert-pheno?icon=docker&label=image%20size)](https://hub.docker.com/r/manuelrueda/convert-pheno/)
[![Documentation Status](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/documentation.yml/badge.svg)](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/documentation.yml)
[![License: Artistic-2.0](https://img.shields.io/badge/License-Artistic%202.0-0298c3.svg)](https://opensource.org/licenses/Artistic-2.0)
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
  - [Non-Containerized](#non-containerized)
  - [Containerized](#containerized)
- [How to run convert-pheno](#how-to-run-convert-pheno)
- [Citation](#citation)
  - [Author](#author)
- [License](#copyright-and-license)

# NAME

convert-pheno - A script to interconvert common data models for phenotypic data

# SYNOPSIS

    convert-pheno [-i input-type] <infile> [-o output-type] <outfile> [-options]

        Arguments:                       
          (input-type): 
                -ibff                    Beacon v2 Models ('individuals' JSON|YAML) file
                -iomop                   OMOP-CDM CSV files or PostgreSQL dump
                -ipxf                    Phenopacket v2 (JSON|YAML) file
                -iredcap (experimental)  REDCap (raw data) export CSV file
                -icdisc  (experimental)  CDISC-ODM v1 XML file
                -icsv    (experimental)  Raw data CSV

                (Wish-list)
                #-iopenehr               openEHR

          (output-type):
                -obff                    Beacon v2 Models ('individuals' JSON|YAML) file
                -opxf                    Phenopacket v2 (JSON|YAML) file
                -oomop   (experimental)  Prefix for OMOP-CDM tables (CSV)

                Compatible with -i(bff|pxf):
                -ocsv                    Flatten data to CSV
                -ojsonf                  Flatten data to 1D-JSON (or 1D-YAML if suffix is .yml|.yaml)
                -ojsonld (experimental)  JSON-LD (interoperable w/ RDF ecosystem; YAML-LD if suffix is .ymlld|.yamlld)

        Options:
          -exposures-file <file>         CSV file with a list of 'concept_id' considered to be exposures (with -iomop)
          -levenshtein-weight <weight>   Set the normalized Levenshtein weight for fuzzy search composite scoring (default: 0.1, range: 0-1)
          -mapping-file <file>           Fields mapping YAML (or JSON) file
          -max-lines-sql <number>        Maximum lines read per table from SQL dump [500]
          -min-text-similarity-score <score> Minimum score for cosine similarity (or Sorensen-Dice coefficient) [0.8] (to be used with --search [mixed|fuzzy])
          -ohdsi-db                      Use Athena-OHDSI database (~2.2GB) with -iomop
          -omop-tables <tables>          OMOP-CDM tables to be processed. Tables <CONCEPT> and <PERSON> are always included.
          -out-dir <directory>           Output (existing) directory
          -O                             Overwrite output file
          -path-to-ohdsi-db <directory>  Directory for the file <ohdsi.db>
          -phl|print-hidden-labels       Print original values (before DB mapping) of text fields <_labels>
          -rcd|redcap-dictionary <file>  REDCap data dictionary CSV file
          -schema-file <file>            Alternative JSON Schema for mapping file
          -search <type>                 Type of search [>exact|mixed|fuzzy]
          -svs|self-validate-schema      Perform a self-validation of the JSON schema that defines mapping (requires IO::Socket::SSL)
          -sep|separator <char>          Delimiter character for CSV files [;] e.g., --sep $'\t'
          -stream                        Enable incremental processing with -iomop and -obff [>no-stream|stream]
          -sql2csv                       Print SQL TABLES (only valid with -iomop). Mutually exclusive with --stream
          -test                          Does not print time-changing-events (useful for file-based cmp)
          -text-similarity-method <method> The method used to compare values to DB [>cosine|dice]
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

# SUMMARY

`convert-pheno` is a command-line front-end to the CPAN's module [Convert::Pheno](https://metacpan.org/pod/Convert%3A%3APheno) to interconvert common data models for phenotypic data.

# INSTALLATION

If you plan to only use the CLI, we recommend installing it via CPAN. See details below.

## Non containerized

The script runs on command-line Linux and it has been tested on Debian/RedHat/MacOS based distributions (only showing commands for Debian's). Perl 5 is installed by default on Linux, 
but we will install a few CPAN modules with `cpanminus`.

### Method 1: From CPAN

First install system level dependencies:

    sudo apt-get install cpanminus libbz2-dev zlib1g-dev libperl-dev libssl-dev

Now you have two choose between one of the 2 options below:

**Option 1:** Install Convert-Pheno and the dependencies at `~/perl5`

    cpanm --local-lib=~/perl5 local::lib && eval $(perl -I ~/perl5/lib/perl5/ -Mlocal::lib)
    cpanm --notest Convert::Pheno
    convert-pheno --help

To ensure Perl recognizes your local modules every time you start a new terminal, you should type:

    echo 'eval $(perl -I ~/perl5/lib/perl5/ -Mlocal::lib)' >> ~/.bashrc

To **update** to the newest version:

    cpanm Convert::Pheno

**Option 2:** Install Convert-Pheno and the dependencies in a "virtual environment" (at `local/`) . We'll be using the module `Carton` for that:

    mkdir local
    cpanm --notest --local-lib=local/ Carton
    echo "requires 'Convert::Pheno';" > cpanfile
    export PATH=$PATH:local/bin; export PERL5LIB=$(pwd)/local/lib/perl5:$PERL5LIB
    carton install
    carton exec -- convert-pheno -help

### Method 2: From CPAN in a Conda environment

Please follow [these instructions](https://cnag-biomedical-informatics.github.io/convert-pheno/download-and-installation/#__tabbed_1_2).

### Method 3: From Github

To clone the repository for the first time:

    git clone https://github.com/cnag-biomedical-informatics/convert-pheno.git
    cd convert-pheno

To update an existing clone, navigate to the repository folder and run:

    git pull

Install system level dependencies:

    sudo apt-get install cpanminus libbz2-dev zlib1g-dev libperl-dev libssl-dev

Now you have two choose between one of the 2 options below:

**Option 1:** Install the dependencies at `~/perl5`:

    cpanm --local-lib=~/perl5 local::lib && eval $(perl -I ~/perl5/lib/perl5/ -Mlocal::lib)
    cpanm --notest --installdeps .
    bin/convert-pheno --help

To ensure Perl recognizes your local modules every time you start a new terminal, you should type:

    echo 'eval $(perl -I ~/perl5/lib/perl5/ -Mlocal::lib)' >> ~/.bashrc

**Option 2:** Install the dependencies in a "virtual environment" (at `local/`) . We'll be using the module `Carton` for that:

    mkdir local
    cpanm --notest --local-lib=local/ Carton
    export PATH=$PATH:local/bin; export PERL5LIB=$(pwd)/local/lib/perl5:$PERL5LIB
    carton install
    carton exec -- bin/convert-pheno -help

## Containerized

### Method 4: From Docker Hub

(Estimated Time: Approximately 15 seconds)

Download the latest version of the Docker image (supports both amd64 and arm64 architectures) from [Docker Hub](https://hub.docker.com/r/manuelrueda/convert-pheno) by executing:

    docker pull manuelrueda/convert-pheno:latest
    docker image tag manuelrueda/convert-pheno:latest cnag/convert-pheno:latest

See additional instructions below.

### Method 5: With Dockerfile

(Estimated Time: Approximately 3 minutes)

Please download the `Dockerfile` from the repo:

    wget https://raw.githubusercontent.com/cnag-biomedical-informatics/convert-pheno/main/Dockerfile

And then run:

    docker buildx build -t cnag/convert-pheno:latest .

### Additional instructions for Methods 4 and 5

To run the container (detached) execute:

    docker run -tid -e USERNAME=root --name convert-pheno cnag/convert-pheno:latest

To enter:

    docker exec -ti convert-pheno bash

The command-line executable can be found at:

    /usr/share/convert-pheno/bin/convert-pheno

The default container user is `root` but you can also run the container as `$UID=1000` (`dockeruser`). 

     docker run --user 1000 -tid --name convert-pheno cnag/convert-pheno:latest
    

Alternatively, you can use `make` to perform all the previous steps:

    wget https://raw.githubusercontent.com/cnag-biomedical-informatics/convert-pheno/main/Dockerfile
    wget https://raw.githubusercontent.com/cnag-biomedical-informatics/convert-pheno/main/makefile.docker
    make -f makefile.docker install
    make -f makefile.docker run
    make -f makefile.docker enter

### Mounting volumes

Docker containers are fully isolated. If you need the mount a volume to the container please use the following syntax (`-v host:container`). 
Find an example below (note that you need to change the paths to match yours):

    docker run -tid --volume /media/mrueda/4TBT/data:/data --name convert-pheno-mount cnag/convert-pheno:latest

Then I will do something like this:

    # First I create an alias to simplify invocation (from the host)
    alias convert-pheno='docker exec -ti convert-pheno-mount /usr/share/convert-pheno/bin/convert-pheno'

    # Now I use the alias to run the command (note that I use the flag --out-dir to specify the output directory)
    convert-pheno -ibff /data/individuals.json -opxf pxf.json --out-dir /data

### System requirements

    - OS/ARCH supported: B<linux/amd64> and B<linux/arm64>.
    - Ideally a Debian-based distribution (Ubuntu or Mint), but any other (e.g., CentOS, OpenSUSE) should do as well (untested).
      (It should also work on macOS and Windows Server, but we are only providing information for Linux here)
    * Perl 5 (>= 5.26 core; installed by default in most Linux distributions). Check the version with "perl -v".
    * >= 4GB of RAM
    * 1 core
    * At least 16GB HDD

# HOW TO RUN CONVERT-PHENO

For executing convert-pheno you will need:

- Input file(s):

    A text file in one of the accepted formats.

    Note that when using `--iomop`, I/O files can be gzipped.

- Optional: 

    Athena-OHDSI database

    The database file is available at this [link](https://drive.google.com/drive/folders/1-5Ywf-hhwb8bX1sRNV2Tf3EjH4TCaC8P?usp=sharing) (~2.2GB). The database may be needed when using `-iomop`.

    Regardless if you're using the containerized or non-containerized version, the download procedure is the same. For CLI users, Google makes it difficult to use `wget`, `curl` or `aria2c` so we will use a `Python` module instead:

        $ pip install gdown

    And then run the following script

        import gdown

        url = 'https://drive.google.com/uc?export=download&id=1-Ls1nmgxp-iW-8LkRIuNNdNytXa8kgNw'
        output = './ohdsi.db'
        gdown.download(url, output, quiet=False)

    Once downloaded, you have two options:

    a) Move the file `ohdsi.db` inside the `share/db/` directory.

    or

    b) Use the option `--path-to-ohdsi-db`

**Examples:**

Note that you can find input examples for all conversions within the `t/` directory of this repository:

    $ bin/convert-pheno -ipxf t/pxf2bff/in/pxf.json -obff individuals.json

    $ bin/convert-pheno -ibff t/bff2pxf/in/individuals.json -opxf phenopackets.yaml --out-dir my_out_dir 

    $ bin/convert-pheno -iomop t/omop2bff/in/omop_cdm_eunomia.sql -opxf phenopackets.json -max-lines-sql 2694

    $ bin/convert-pheno -ibff t/bff2omop/in/individuals.json -oomop my_prefix --ohdsi-db # Needs ohdsi.db

Generic examples:

    $ $path/convert-pheno -iredcap redcap.csv -opxf phenopackets.json --redcap-dictionary redcap_dict.csv --mapping-file mapping_file.yaml

    $ $path/convert-pheno -iomop dump.sql.gz -obff individuals.json.gz --stream -omop-tables measurement -verbose

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
