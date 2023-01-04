**Convert-Pheno** is actually a Perl [module](https://metacpan.org/search?size=20&q=Convert%3A%3APheno). 

!!! Danger "Disclaimer"
    The module will be available in Comprehensive Perl Archive Network (CPAN) once the accompanying paper is accepted for publication.

The module can be used inside a `Perl` script, but also inside scripts from other languages (e.g., Python), as long as they allow for it. The operation is simple:

=== "Inside Perl"

    Find [here](https://github.com/mrueda/convert-pheno/blob/main/ex/perl.pl) an example script.

=== "Inside Python"

    Find [here](https://github.com/mrueda/convert-pheno/blob/main/ex/python.py) an example script. It should work out of the box with the [containerized version](https://github.com/mrueda/convert-pheno#containerized).

    !!! Success "Perl inside Python, is that even possible :smile:?"
        Perl plays nicely with other languages and let users embed them into Perl's code (e.g., with `Inline`). Unfortunately, embedding Perl code into other languages is not as straightforward.
        Luckily, the library [PyPerler](https://github.com/tkluck/pyperler) solves our problem. It should work out of the box with the [containerized version](https://github.com/mrueda/convert-pheno#containerized).

=== "Other programming languages"

    It is possible to use Perl modules inside other languages. For **Ruby** you can use `ruby-perl` ([link](https://github.com/zephirworks/ruby-perl)) and for **Go** you can use [this library](https://github.com/bradfitz/campher).
