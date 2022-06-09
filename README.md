# NAME

A script that converts Phenopackets PXF (JSON) to BFF (JSON)

# SYNOPSIS

pxf2bff -i <\*.json> \[-options\]

     Arguments:                       
       -i|input                       Phenopackets JSON files

     Options:
       -o|out-dir                     Output (existing) directory for the BFF files
       -h|help                        Brief help message
       -man                           Full documentation
       -debug                         Print debugging (from 1 to 5, being 5 max)
       -verbose                       Verbosity on
     

# CITATION

The author requests that any published work which utilizes Beacon includes a cite to the the following reference:

Rueda, M, Ariosa R. "Beacon v2 Reference Implementation: a software for federated discovery of genomic and phenoclinic data". _Submitted_.

# SUMMARY

A script that converts Phenopackets PXF (JSON) to BFF (JSON).

Note that PXF contain one individual per file (1 JSON document), whereas BFF (majoritarily) contain multiple inviduals per file (JSON array of documentsa). Thus, the input should be PXF JSON from, say, the same dataset, and the output will be a unique `individuals.json` file.

_NB:_ The script was created to parse [RD\_Connect synthetic data](https://ega-archive.org/datasets/EGAD00001008392). See examples in the `in` and `out` directories. The script is **UNTESTED** for other PXFs.

# HOW TO RUN PXF2BFF

The script runs on command-line Linux (tested on Debian-based distribution). Perl 5 is installed by default on Linux, 
but you might need to manually install a few CPAN modules.

    * JSON::XS
    * Path::Tiny
    * Term::ANSIColor

First we install cpanminus (with sudo privileges):

    $ sudo apt-get install cpanminus

Then the modules:

    $ cpanm --sudo JSON::XS Path::Tiny Term::ANSIColor

For executing pxf2bff you will need:

- Input file(s):

    A list of Phenopackets JSON files (normally from the same dataset). Note that PXFs only contain ONE individual per file.

**Examples:**

    $ ./pxf2bff -i in/*json -o out

    $ $path/pxf2bff -i file.json --out-dir my_bff_outdir

    $ $path/pxf2bff -i my_indir/*json -o my_bff_outdir 

## COMMON ERRORS AND SOLUTIONS

    * Error message: Foo
      Solution: Bar

    * Error message: Foo
      Solution: Bar

# AUTHOR 

Written by Manuel Rueda, PhD. Info about CRG can be found at [https://www.crg.eu](https://www.crg.eu).

# REPORTING BUGS

Report bugs or comments to <manuel.rueda@crg.eu>.

# COPYRIGHT

This PERL file is copyrighted. See the LICENSE file included in this distribution.
