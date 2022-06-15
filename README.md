# NAME

**UNDER DEVELOPMENT**

convert-pheno - A Perl script to interconvert phenotypic data between different CDM formats

# SYNOPSIS

convert-pheno \[-i input-type\] &lt;infile> \[-o output-type\] &lt;outfile> \[-options\]

     Arguments:                       
       -input-type:  
             -ipxf                    Phenopackets JSON file(s)
             -ibff                    Beacon v2 JSON file (JSON array)

            (Wish-list)
             #-iomop                  OMOP-CDM csv file
             #-icdisc                 CDISC csv file
             #-ifhir                  FHIR csv file
             #-iredcap                RedCap csv file
       -output-type;
             -opxf                    Phenopackets JSON file (JSON array)
             -obff                    Beacon v2 JSON file (JSON array)

             (Wish-list)
             #-oomop                  OMOP-CDM csv file
             #-ocdisc                 CDISC csv file
             #-ofhir                  FHIR csv file
             #-oredcap                RedCap csv file

     Options:
       -out-dir                       Output (existing) directory
       -h|help                        Brief help message
       -man                           Full documentation
       -debug                         Print debugging (from 1 to 5, being 5 max)
       -verbose                       Verbosity on
     

# DESCRIPTION

convert-pheno  is a commandline frontend to the module Convert::Pheno.

# CITATION

To be defined.

# SUMMARY

A script that uses Convert::Pheno to interconverts phenotypic data between different CDM formats

_NB:_ If the input file consists of is a JSON array the output file will also be a JSON array.

# HOW TO RUN PHENO-CONVERT

The script runs on command-line Linux (tested on Debian-based distribution). Perl 5 is installed by default on Linux, 
but we will install a few CPAN modules with `cpanminus`.

First we install cpanminus (with sudo privileges):

    $ sudo apt-get install cpanminus

Then the modules:

    $ cpanm --sudo --installdeps .

If you prefer to have the dependencies in a "virtual environment" (i.e., install the CPAN modules in the directory of the application) we recommend using the module `Carton`.

    $ cpanm --sudo Carton

Then, we can install our dependencies:

    $ carton install

For executing convert-pheno you will need:

- Input file(s):

    A list of Phenopackets JSON files (normally from the same dataset). Note that PXFs only contain ONE individual per file.

**Examples:**

    $ ./convert-pheno -ipxf in/*json -obff individuals.json

    $ $path/convert-pheno -ipxf file.json -obff individuals.json --out-dir my_bff_outdir

    $ $path/convert-pheno -ibff individuals.json -opxf phenopackets.json

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
