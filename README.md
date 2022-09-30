# NAME

**UNDER DEVELOPMENT**

convert-pheno - A script to interconvert common data models for phenotypic data

# SYNOPSIS

convert-pheno \[-i input-type\] &lt;infile> \[-o output-type\] &lt;outfile> \[-options\]

     Arguments:                       
       -input-type:  
             -ibff                    Beacon v2 JSON file
             -iomop                   OMOP-CDM CSV files or PostgreSQL dump
             -ipxf                    Phenopacket v2 JSON file
             -iredcap                 REDCap (raw data) export CSV file

            (Under development)
             #-icdisc                 CDISC-ODM XML file

            (Wish-list)
             #-ifhir                  HL7/FHIR

       -output-type;
             -obff                    Beacon v2 JSON file
             -opxf                    Phenopacket v2 JSON file

     Options:
       -debug                         Print debugging (from 1 to 5, being 5 max)
       -format                        Output format for the text file [>json|yaml]
       -h|help                        Brief help message
       -man                           Full documentation
       -nc|-no-color                  Don't print colors to STDOUT
       -ohdsi-db                      Use Athena-OHDSI database (~1.2GB) with -iomop
       -out-dir                       Output (existing) directory
       -phl|print-hidden-labels       Print original values (before DB mapping) of text fields <_labels>
       -rcd|redcap-dictionary         REDCap data dictionary CSV file
       -sep|separator                 Delimiter character for CSV files
       -sql2csv                       Print SQL TABLES (with -iomop)
       -test                          Does not print time-changing-events
       -verbose                       Verbosity on
       -v                             Print Version

# DESCRIPTION

`convert-pheno` is a command-line front-end to the CPAN's module [Convert::Pheno](https://metacpan.org/pod/Convert%3A%3APheno).

The module will be uploaded to CPAN once the paper is submitted.

Please see a more comprehensive documentation [here](https://convert-pheno.readthedocs.io/en/latest).

# SUMMARY

A script that uses [Convert::Pheno](https://metacpan.org/pod/Convert%3A%3APheno) to interconvert common data models for phenotypic data

# INSTALLATION

## Containerized

Please download the `Dockerfile` from the repo:

    wget https://raw.githubusercontent.com/mrueda/Convert-Pheno/main/Dockerfile

And then run:

    docker build -t cnag/convert-pheno:latest .

To run the container (detached) execute:

    docker run -tid --name convert-pheno cnag/convert-pheno:latest

To enter:

    docker exec -ti convert-pheno bash

The command-line executable can be found at:

    /usr/share/convert-pheno/bin/convert-pheno

_NB:_ Docker containers are fully isolated. If you need the mount a volume to the container please use the following syntax (`-v host:container`). Find an example below (note that you need to change the paths to match yours):

    docker run -tid --volume /media/mrueda/4TBT:/4TB --name convert-pheno cnag/convert-pheno:latest

## Non containerized

The script runs on command-line Linux (tested on Debian-based distribution). Perl 5 is installed by default on Linux, 
but we will install a few CPAN modules with `cpanminus`.

First we install cpanminus (with sudo privileges):

    sudo apt-get install cpanminus

Then the modules:

    cpanm --sudo --installdeps .

_NB:_ If you have downloaded this from CPAN or GitHub's main branch it's unlikely that you have installation errors. In any case, tests can be performed by using:

    prove -l

If you prefer to have the dependencies in a "virtual environment" (i.e., install the CPAN modules in the directory of the application) we recommend using the module `Carton`.

    cpanm --sudo Carton

Then, we can install our dependencies:

    carton install

# HOW TO RUN CONVERT-PHENO

For executing convert-pheno you will need:

- Input file(s):

    A text file in one of the accepted formats.

- Optional: 

    Athena-OHDSI database

    Please download it from this [link](https://drive.google.com/file/d/104ciON3zRc3ScAzzrL_3GO14aCnBLh-c/view?usp=sharing) (~1.2GB) and move it inside `db/` directory.

**Examples:**

    $ bin/convert-pheno -ipxf phenopackets.json -obff individuals.json

    $ $path/convert-pheno -ibff individuals.json -opxf phenopackets.json --out-dir my_out_dir

    $ $path/convert-pheno -iredcap redcap.csv -opxf phenopackets.json --redcap-dictionary redcap_dict.csv

    $ $path/convert-pheno -iomop dump.sql -obff individuals.json 

    $ $path/convert-pheno -iomop *csv -obff individuals.json -sep ','

    $ carton exec -- $path/convert-pheno -ibff individuals.json -opxf phenopackets.json # If using Carton

## COMMON ERRORS AND SOLUTIONS

    * Error message: Foo
      Solution: Bar

    * Error message: Foo
      Solution: Bar

# CITATION

The author requests that any published work that utilizes `Convert-Pheno` includes a cite to the the following reference:

Rueda, M., (2022). Convert-Pheno: A toolbox to interconvert common data models for phenotypic data \[Software\]. Available from https://github.com/mrueda/Convert-Pheno

# AUTHOR 

Written by Manuel Rueda, PhD. Info about CNAG can be found at [https://www.cnag.crg.eu](https://www.cnag.crg.eu).

# REPORTING BUGS

Report bugs or comments to <manuel.rueda@cnag.crg.eu>.

# COPYRIGHT

This PERL file is copyrighted. See the LICENSE file included in this distribution.
