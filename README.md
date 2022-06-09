# NAME

**UNDER DEVELOPMENT**

**WARNING** DO NOT TRY THIS AT HOME

A script that converts Common Data Models formats

# SYNOPSIS

pheno-convert \[-i input-type\] &lt;infile> \[-o output-type\] &lt;outfile> \[-options\]

     Arguments:                       
       -i|input
            Formats:  
              -ipxf                   Phenopackets JSON file(s)
              -ibff                   Beacon v2 JSON filei (JSON array)

            (Wish-list)
             #-iomop                  OMOP-CDM csv file
             #-icdisc                 CDISC csv file
             #-ifhir                  FHIR csv file
             #-iredcap                RedCap csv file
       -o|output
            Formats:  
              -opxf                   Phenopackets JSON file (JSON array)
              -obff                   Beacon v2 JSON file (JSON array)

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
     

# CITATION

To be defined.

# SUMMARY

A script that converts Common Data Models formats.

_NB:_If the input file consists of is a JSON array the output file will also be a JSON array.

# HOW TO RUN PHENO-CONVERT

The script runs on command-line Linux (tested on Debian-based distribution). Perl 5 is installed by default on Linux, 
but we will install a few CPAN modules with `cpanminus`.

First we install cpanminus (with sudo privileges):

    $ sudo apt-get install cpanminus

Then the modules:

    $ cpanm --sudo --installdeps .

For executing pheno-convert you will need:

- Input file(s):

    A list of Phenopackets JSON files (normally from the same dataset). Note that PXFs only contain ONE individual per file.

**Examples:**

    $ ./pheno-convert -ipxf in/*json -obff individuals.json

    $ $path/pheno-convert -ipxf file.json -obff individuals.json --out-dir my_bff_outdir

    $ $path/pheno-convert -ibff individuals.json -opxf phenopackets.json

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
