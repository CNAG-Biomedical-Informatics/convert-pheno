# Command-line tool

`Convert-Pheno` comes with a command-line utility. Using it as a command line tool works well when your input are **text files**, for instance, those coming from a PostgreSQL export.

The operation is simple:

    $ convert-pheno -input-format <filein> -output-format <fileout>

Please see more examples in this [README](https://github.com/mrueda/convert-pheno#synopsis).

!!! Note "Inspiration"
    The command line operation was inspired by `convert` tool from [ImageMagick](https://imagemagick.org/script/convert.php) and from [OpenBabel](https://openbabel.org/wiki/Main_Page).
