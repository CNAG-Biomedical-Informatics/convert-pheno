**Convert-Pheno** is actually a Perl [module](https://metacpan.org/search?size=20&q=Convert%3A%3APheno). 

!!! Danger "Disclaimer"
    The module will be available in Comprehensive Perl Archive Network (CPAN) once the accompanying paper is accepted for publication.

## Usage

The module can be used within a `Perl` script, but it can also be utilized in scripts written in other languages, such as `Python`. 

=== "Inside Perl"

    Find [here](https://github.com/cnag-biomedical-informatics/convert-pheno/blob/main/ex/perl.pl) an example script.

=== "Inside Python"

    Find [here](https://github.com/cnag-biomedical-informatics/convert-pheno/blob/main/ex/python.py) an example script. It should work out of the box with the [containerized version](https://github.com/cnag-biomedical-informatics/convert-pheno#containerized).

    !!! Question "Perl inside Python, is that even possible :smile:?"
        Perl easily integrates with other languages and allows for embedding them into Perl code (e.g., using `Inline`). However, embedding Perl code into other languages is not as simple. Fortunately, the [PyPerler library](https://github.com/tkluck/pyperler) provides a solution for this issue. It should work out of the box with the [containerized version](https://github.com/cnag-biomedical-informatics/convert-pheno#containerized).

=== "Other programming languages"

    It is possible to use Perl modules inside other languages. For **Ruby** you can use `ruby-perl` ([link](https://github.com/zephirworks/ruby-perl)) and for **Go** you can use [this library](https://github.com/bradfitz/campher).
