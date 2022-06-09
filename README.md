# NAME

**UNDER DEVELOPMENT**

A script that converts Common Data Models formats

# SYNOPSIS

pheno-convert -i <\*.json> \[-options\]

     Arguments:                       
       -i|input                       Phenopackets JSON files

     Options:
       -o|out-dir                     Output (existing) directory for the BFF files
       -h|help                        Brief help message
       -man                           Full documentation
       -debug                         Print debugging (from 1 to 5, being 5 max)
       -verbose                       Verbosity on
     

# CITATION

To be defined.

# SUMMARY

A script that converts Common Data Models formats

# HOW TO RUN PHENO-CONVERT

The script runs on command-line Linux (tested on Debian-based distribution). Perl 5 is installed by default on Linux, 
but you might need to manually install a few CPAN modules.

    * JSON::XS
    * Path::Tiny
    * Term::ANSIColor

First we install cpanminus (with sudo privileges):

    $ sudo apt-get install cpanminus

Then the modules:

    $ cpanm --sudo JSON::XS Path::Tiny Term::ANSIColor

For executing pheno-convert you will need:

- Input file(s):

    A list of Phenopackets JSON files (normally from the same dataset). Note that PXFs only contain ONE individual per file.

**Examples:**

    $ ./pheno-convert -i in/*json -o out

    $ $path/pheno-convert -i file.json --out-dir my_bff_outdir

    $ $path/pheno-convert -i my_indir/*json -o my_bff_outdir 

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
