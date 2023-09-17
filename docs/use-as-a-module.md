`Convert-Pheno` core is a Perl module available at [CPAN](https://metacpan.org/search?size=20&q=Convert%3A%3APheno). 

## Usage

The module can be used within a `Perl` script, but it can also be utilized in scripts written in other languages, such as `Python`. 

=== "Inside Perl"

    Find [here](https://github.com/cnag-biomedical-informatics/convert-pheno/blob/main/share/ex/perl.pl) an example script.

=== "Inside Python"

    Find [here](https://github.com/cnag-biomedical-informatics/convert-pheno/blob/main/share/ex/python.py) an example script. 

    * It should work out of the box with the [containerized version](https://github.com/CNAG-Biomedical-Informatics/convert-pheno#containerized-recommended-method). 
    * You also have instructions in how to run it in a [conda environment](./download-and-installation.md#non-containerized).

    !!! Question "Perl inside Python, is that even possible :smile:?"
        Perl easily integrates with other languages and allows for embedding them into Perl code (e.g., using `Inline`). However, embedding Perl code into other languages is not as simple. Fortunately, the [PyPerler library](https://github.com/tkluck/pyperler) provides a solution for this issue.
