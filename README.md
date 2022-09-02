# NAME

**UNDER DEVELOPMENT**

convert-pheno - A script to interconvert phenotypic data between different CDM formats

# SYNOPSIS

convert-pheno \[-i input-type\] &lt;infile> \[-o output-type\] &lt;outfile> \[-options\]

     Arguments:                       
       -input-type:  
             -ibff                    Beacon v2 JSON file
             -iomop                   OMOP-CDM CSV files or SQL dump
             -ipxf                    Phenopacket JSON file
             -iredcap                 REDCap CSV file

            (Wish-list)
             #-icdisc                 CDISC CSV file
             #-ifhir                  FHIR CSV file

       -output-type;
             -obff                    Beacon v2 JSON file
             -opxf                    Phenopacket JSON file

     Options:
       -out-dir                       Output (existing) directory
       -h|help                        Brief help message
       -man                           Full documentation
       -debug                         Print debugging (from 1 to 5, being 5 max)
       -verbose                       Verbosity on
       -nc|-no-color                  Don't print colors to STDOUT
       -format                        Output format for the text file [>json|yaml]
       -rcd|redcap-dictionary         Dictionary file (CSV) exported from REDCap
       -phl|print-hidden-labels       Print original values (before DB mapping) of text fields <_labels>
       -sep|separator                 Delimiter character for CSV files
     

# DESCRIPTION

`convert-pheno` is a command-line front-end to the CPAN's module [Convert::Pheno](https://metacpan.org/pod/Convert%3A%3APheno).

The module will be uploaded to CPAN once ready.

# CITATION

The author requests that any published work that utilizes `Convert-Pheno` includes a cite to the the following reference:

Rueda, M. "Convert-Pheno: A toolbox to interconvert common data models for phenotypic data". _Manuscript in preparation_.

# SUMMARY

A script that uses [Convert::Pheno](https://metacpan.org/pod/Convert%3A%3APheno) to interconvert phenotypic data between different CDM formats

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

## Non containerized

The script runs on command-line Linux (tested on Debian-based distribution). Perl 5 is installed by default on Linux, 
but we will install a few CPAN modules with `cpanminus`.

First we install cpanminus (with sudo privileges):

    sudo apt-get install cpanminus

Then the modules:

    cpanm --sudo --installdeps .

If you prefer to have the dependencies in a "virtual environment" (i.e., install the CPAN modules in the directory of the application) we recommend using the module `Carton`.

    cpanm --sudo Carton

Then, we can install our dependencies:

    carton install

# HOW TO RUN PHENO-CONVERT

For executing convert-pheno you will need:

- Input file(s):

    A text file in one of the accepted formats.

**Examples:**

    $ bin/convert-pheno -ipxf phenopackets.json -obff individuals.json

    $ $path/convert-pheno -ibff individuals.json -obff phenopackets.json --out-dir my_out_dir

    $ $path/convert-pheno -iredcap redcap.csv -opxf phenopackets.json --redcap-dictionary redcap_dict.csv

    $ $path/convert-pheno -iomop dump.sql -obff individuals.json 

    $ $path/convert-pheno -iomop *csv -obff individuals.json -sep ','

    $ carton exec -- $path/convert-pheno -ibff individuals.json -opxf phenopackets.json # If using Carton

## COMMON ERRORS AND SOLUTIONS

    * Error message: Foo
      Solution: Bar

    * Error message: Foo
      Solution: Bar

# AUTHOR 

Written by Manuel Rueda, PhD. Info about CNAG can be found at [https://www.cnag.crg.eu](https://www.cnag.crg.eu).

# REPORTING BUGS

Report bugs or comments to <manuel.rueda@cnag.crg.eu>.

# COPYRIGHT

This PERL file is copyrighted. See the LICENSE file included in this distribution.
