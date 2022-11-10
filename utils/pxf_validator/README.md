# NAME

pxf-validator: A script that validates PXF JSON files against PXF v2 JSON schema.

# SYNOPSIS

pxf-validator -i <\*json> \[-options\]

     Arguments:                       
       -i|input                       Phenopacket JSON file(s)

     Options:
       -s|schema-dir                  Directory with Phenopacket v2 JSON schema 
       -h|help                        Brief help message
       -man                           Full documentation
       -debug                         Print debugging (from 1 to 5, being 5 max)
       -verbose                       Verbosity on
       -nc|-no-color                  Don't print colors to STDOUT

# DESCRIPTION

pxf-validator: A script that validates PXF JSON files against PXF v2 JSON schema.

# SUMMARY

pxf-validator: A script that validates PXF JSON files against PXF v2 JSON schema.

# INSTALLATION

The script runs on command-line Linux (tested on Debian-based distribution). Perl 5 is installed by default on Linux, 
but we will install a few CPAN modules with `cpanminus`.

Please download the `cpanfile` from the repo:

    wget https://raw.githubusercontent.com/mrueda/convert-pheno/main/cpanfile

First we install cpanminus (with sudo privileges):

    sudo apt-get install cpanminus

Then the modules:

    cpanm --sudo --installdeps .

If you prefer to have the dependencies in a "virtual environment" (i.e., install the CPAN modules in the directory of the application) we recommend using the module `Carton`.

    cpanm --sudo Carton

Then, we can install our dependencies:

    carton install

# HOW TO RUN PXF-VALIDATOR

For executing convert-pheno you will need:

- Input file(s):

    A Phenopacket file(s) in JSON format.

**Examples:**

    $ pxf-validator -i phenopackets.json 

    $ $path/pxf-validator -i phenopackets*.json

    $ carton exec -- $path/pxf-validator -i phenopackets.json # If using Carton

## COMMON ERRORS AND SOLUTIONS

The validator is based on JSON Schema, thus, the validation is only as good as the artificially-created JSON schema.

    * NB: Phenopackets v2 does not allow for additional properties at the root level. Required properties: [ "id", "metaData" ].
          At the 2nd level, "metaData" does not allow for additional properties.

    * Error message: Foo
      Solution: Bar

    * Error message: Foo
      Solution: Bar

# CITATION

The author requests that any published work that utilizes `Convert-Pheno` includes a cite to the the following reference:

Rueda, M., (2022). Convert-Pheno: A toolbox to interconvert common data models for phenotypic data \[Software\]. Available from https://github.com/mrueda/convert-pheno

# AUTHOR 

Written by Manuel Rueda, PhD. Info about CNAG can be found at [https://www.cnag.crg.eu](https://www.cnag.crg.eu).

# COPYRIGHT AND LICENSE

This PERL file is copyrighted. See the LICENSE file included in this distribution.
