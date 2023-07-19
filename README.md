<p align="left">
  <a href="https://github.com/cnag-biomedical-informatics/convert-pheno"><img src="https://github.com/cnag-biomedical-informatics/convert-pheno/blob/main/docs/img/CP-logo.png" width="220" alt="Convert-Pheno"></a>
  <a href="https://github.com/cnag-biomedical-informatics/convert-pheno"><img src="https://github.com/cnag-biomedical-informatics/convert-pheno/blob/main/docs/img/CP-text.png" width="500" alt="Convert-Pheno"></a>
</p>
<p align="center">
    <em>A software toolkit for the interconversion of standard data models for phenotypic data</em>
</p>

[![Build and Test](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/build-and-test.yml/badge.svg)](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/build-and-test.yml)
[![Coverage Status](https://coveralls.io/repos/github/CNAG-Biomedical-Informatics/convert-pheno/badge.svg?branch=main)](https://coveralls.io/github/CNAG-Biomedical-Informatics/convert-pheno?branch=main)
[![CPAN Publish](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/cpan-publish.yml/badge.svg)](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/cpan-publish.yml)
[![Kwalitee Score](https://cpants.cpanauthors.org/dist/Convert-Pheno.svg)](https://cpants.cpanauthors.org/dist/Convert-Pheno)
![version](https://img.shields.io/badge/version-0.12_beta-orange)
[![Docker Build](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/docker-build.yml/badge.svg)](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/docker-build.yml)
[![Docker Pulls](https://badgen.net/docker/pulls/manuelrueda/convert-pheno?icon=docker&label=pulls)](https://hub.docker.com/r/manuelrueda/convert-pheno/)
[![Docker Image Size](https://badgen.net/docker/size/manuelrueda/convert-pheno?icon=docker&label=image%20size)](https://hub.docker.com/r/manuelrueda/convert-pheno/)
[![Documentation Status](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/documentation.yml/badge.svg)](https://github.com/cnag-biomedical-informatics/convert-pheno/actions/workflows/documentation.yml)
[![License: Artistic-2.0](https://img.shields.io/badge/License-Artistic%202.0-0298c3.svg)](https://opensource.org/licenses/Artistic-2.0)


**Documentation**: <a href="https://cnag-biomedical-informatics.github.io/convert-pheno" target="_blank">https://cnag-biomedical-informatics.github.io/convert-pheno</a>

**CLI Source Code**: <a href="https://github.com/cnag-biomedical-informatics/convert-pheno" target="_blank">https://github.com/cnag-biomedical-informatics/convert-pheno</a>

**Web App UI Source Code**: <a href="https://github.com/cnag-biomedical-informatics/convert-pheno-ui" target="_blank">https://github.com/cnag-biomedical-informatics/convert-pheno-ui</a>

**CPAN Module**: <a href="https://metacpan.org/pod/Convert::Pheno" target="_blank">https://metacpan.org/pod/Convert::Pheno</a>


# NAME

convert-pheno - A script to interconvert common data models for phenotypic data

# SYNOPSIS

convert-pheno \[-i input-type\] &lt;infile> \[-o output-type\] &lt;outfile> \[-options\]

     Arguments:                       
       (input-type): 
             -ibff                    Beacon v2 Models ("individuals" JSON|YAML) file
             -iomop                   OMOP-CDM CSV files or PostgreSQL dump
             -ipxf                    Phenopacket v2 (JSON|YAML) file
             -iredcap (experimental)  REDCap (raw data) export CSV file
             -icdisc  (experimental)  CDISC-ODM v1 XML file

             (Wish-list)
             #-openehr                openEHR
             #-ifhir                  HL7/FHIR

       (output-type):
             -obff                    Beacon v2 Models ("invididuals" JSON|YAML) file
             -opxf                    Phenopacket v2 (JSON|YAML) file

             (Wish-list)
             #-oomop                  OMOP-CDM PostgreSQL dump

     Options:
       -exposures-file                CSV file with a list of 'concept_id' considered to be exposures (with -iomop)
       -mapping-file                  Fields mapping YAML (or JSON) file
       -max-lines-sql                 Maximum number of lines read from SQL dump [500]
       -min-text-similarity-score     Minimum score for cosine similarity (or Sorensen-Dice coefficient) [0.8] (to be used with --search mixed)
       -ohdsi-db                      Use Athena-OHDSI database (~2.2GB) with -iomop
       -omop-tables                   (Only valid with -iomop) OMOP-CDM tables to be processed. Tables <CONCEPT> and <PERSON> are always included.
       -out-dir                       Output (existing) directory
       -O                             Overwrite output file
       -path-to-ohdsi-db              Directory for the file <ohdsi.db>
       -phl|print-hidden-labels       Print original values (before DB mapping) of text fields <_labels>
       -rcd|redcap-dictionary         REDCap data dictionary CSV file
       -schema-file                   Alternative JSON Schema for mapping file
       -search                        Type of search [>exact|mixed]
       -svs|self-validate-schema      Perform a self-validation of the JSON schema that defines mapping (requires IO::Socket::SSL)
       -sep|separator                 Delimiter character for CSV files [;] e.g., --sep $'\t'
       -stream                        Enable incremental processing with -iomop and -obff [>no-stream|stream]
       -sql2csv                       Print SQL TABLES (only valid with -iomop). Mutually exclusive with --stream
       -test                          Does not print time-changing-events (useful for file-based cmp)
       -text-similarity-method        The method used to compare values to DB [>cosine|dice]
       -u|username                    Set the username

     Generic Options:
       -debug                         Print debugging level (from 1 to 5, being 5 max)
       -help                          Brief help message
       -log                           Save log file (JSON). If no argument is given then the log is named [convert-pheno-log.json]
       -man                           Full documentation
       -no-color                      Don't print colors to STDOUT [>color|no-color]
       -v|verbose                     Verbosity on
       -V|version                     Print Version

# DESCRIPTION

`convert-pheno` is a command-line front-end to the CPAN's module [Convert::Pheno](https://metacpan.org/pod/Convert%3A%3APheno).

# SUMMARY

A script that uses [Convert::Pheno](https://metacpan.org/pod/Convert%3A%3APheno) to interconvert common data models for phenotypic data

# INSTALLATION

## Containerized (Recommended Method)

### Method 1: From Docker Hub

Download a docker image (latest version) from [Docker Hub](https://hub.docker.com/r/manuelrueda/convert-pheno) by executing:

    docker pull manuelrueda/convert-pheno:latest
    docker image tag manuelrueda/convert-pheno:latest cnag/convert-pheno:latest

See additional instructions below.

### Method 2: With Dockerfile

Please download the `Dockerfile` from the repo:

    wget https://raw.githubusercontent.com/cnag-biomedical-informatics/convert-pheno/main/Dockerfile

And then run:

    docker build -t cnag/convert-pheno:latest .

### Additional instructions for Methods 1 and 2

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

## Non containerized

The script runs on command-line Linux and it has been tested on Debian/RedHat/MacOS based distributions (only showing commands for Debian's). Perl 5 is installed by default on Linux, 
but we will install a few CPAN modules with `cpanminus`.

### From Github

    git clone https://github.com/cnag-biomedical-informatics/convert-pheno.git
    cd convert-pheno

Install system level dependencies:

    sudo apt-get install cpanminus libbz2-dev zlib1g-dev libperl-dev libssl-dev

Now you have two choose between one of the 3 options below:

**Option 1:** Install dependencies (they're harmless to your system) as `sudo`:

    cpanm --notest --sudo --installdeps .
    bin/convert-pheno --help            

**Option 2:** Install the dependencies at `~/perl5`:

    cpanm --local-lib=~/perl5 local::lib && eval $(perl -I ~/perl5/lib/perl5/ -Mlocal::lib)
    cpanm --notest --installdeps .
    bin/convert-pheno --help

**Option 3:** Install the dependencies in a "virtual environment" (at `local/`) . We'll be using the module `Carton` for that:

    mkdir local
    cpanm --notest --local-lib=local/ Carton
    export PATH=$PATH:local/bin; export PERL5LIB=$(pwd)/local/lib/perl5:$PERL5LIB
    carton install
    carton exec -- bin/convert-pheno -help

### From CPAN

First install system level dependencies:

    sudo apt-get install cpanminus libbz2-dev zlib1g-dev libperl-dev libssl-dev

Now you have two choose between one of the 3 options below:

**Option 1:** System-level installation:

    cpanm --notest --sudo Convert::Pheno
    convert-pheno -h

**Option 2:** Install Convert-Pheno and the dependencies at `~/perl5`

    cpanm --local-lib=~/perl5 local::lib && eval $(perl -I ~/perl5/lib/perl5/ -Mlocal::lib)
    cpanm --notest Convert::Pheno
    convert-pheno --help

**Option 3:** Install Convert-Pheno and the dependencies in a "virtual environment" (at `local/`) . We'll be using the module `Carton` for that:

    mkdir local
    cpanm --notest --local-lib=local/ Carton
    echo "requires 'Convert::Pheno';" > cpanfile
    export PATH=$PATH:local/bin; export PERL5LIB=$(pwd)/local/lib/perl5:$PERL5LIB
    carton install
    carton exec -- convert-pheno -help

### System requirements

    * Ideally a Debian-based distribution (Ubuntu or Mint), but any other (e.g., CentOs, OpenSuse) should do as well.
    * Perl 5 (>= 5.26 core; installed by default in most Linux distributions). Check the version with "perl -v".
    * >= 4GB of RAM
    * 1 core
    * At least 16GB HDD

# HOW TO RUN CONVERT-PHENO

For executing convert-pheno you will need:

- Input file(s):

    A text file in one of the accepted formats. With `--iomop` I/O files can be gzipped.

- Optional: 

    Athena-OHDSI database

    The database file is available at this [link](https://drive.google.com/drive/folders/104_Bgl3IxM3U6u-wn-1LUvNZXevD2DRm?usp=sharing) (~2.2GB). The database may be needed when using `-iomop`.

    Regardless if you're using the containerized or non-containerized version, the download procedure is the same. In Linux you can use `wget`, `curl` or `aria2c`:

        $ wget 'https://drive.google.com/uc?export=download&id=104ciON3zRc3ScAzzrL_3GO14aCnBLh-c&confirm=t' -O ohdsi.db
        or
        $ curl -L 'https://drive.google.com/uc?export=download&id104ciON3zRc3ScAzzrL_3GO14aCnBLh-c' > ohdsi.db
        or
        $ aria2c -x2 'https://drive.google.com/uc?export=download&id=104ciON3zRc3ScAzzrL_3GO14aCnBLh-c&confirm=t' -o ohdsi.db

    (you can install `wget`, `curl` or `aria2c` inside the container by typing `sudo apt install wget`, `sudo apt install curl` or `sudo apt install aria2`.

    Once downloaded, you have two options:

    a) Move the file `ohdsi.db` inside the `share/db/` directory.

    or

    b) Use the option `--path-to-ohdsi-db`

**Examples:**

    $ bin/convert-pheno -ipxf phenopackets.json -obff individuals.json

    $ $path/convert-pheno -ibff individuals.json -opxf phenopackets.yaml --out-dir my_out_dir 

    $ $path/convert-pheno -iredcap redcap.csv -opxf phenopackets.json --redcap-dictionary redcap_dict.csv --mapping-file mapping_file.yaml

    $ $path/convert-pheno -iomop dump.sql -obff individuals.json

    $ $path/convert-pheno -iomop dump.sql.gz -obff individuals.json.gz --stream -omop-tables measurement -verbose

    $ $path/convert-pheno -cdisc cdisc_odm.xml -obff individuals.json --rcd redcap_dict.csv --mapping-file mapping_file.yaml --search mixed --min-text-similarity-score 0.6

    $ $path/convert-pheno -iomop *csv -obff individuals.json -sep ','

    $ carton exec -- $path/convert-pheno -ibff individuals.json -opxf phenopackets.json # If using Carton

## COMMON ERRORS AND SOLUTIONS

    * Error message: CSV_XS ERROR: 2023 - EIQ - QUO character not allowed @ rec 1 pos 21 field 1
      Solution: Make sure you use the right character separator for your data. The script tries to guess it from the file extension (e.g. comma for csv), but sometimes extension and actual separator do not match.
      Example for tab separator in CLI.
       --sep  $'\t' 

    * Error message: Foo
      Solution: Bar

# CITATION

The author requests that any published work that utilizes `Convert-Pheno` includes a cite to the the following reference:

Rueda, M et al., (2023). Convert-Pheno: A software toolkit for the interconversion of standard data models for phenotypic data \[Software\]. Available from https://github.com/cnag-biomedical-informatics/convert-pheno

# AUTHOR 

Written by Manuel Rueda, PhD. Info about CNAG can be found at [https://www.cnag.eu](https://www.cnag.eu).

# COPYRIGHT AND LICENSE

Copyright (C) 2022-2023, Manuel Rueda - CNAG.

This program is free software, you can redistribute it and/or modify it under the terms of the [Artistic License version 2.0](https://metacpan.org/pod/perlartistic).
