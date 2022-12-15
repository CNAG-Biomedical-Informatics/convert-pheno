# As a Perl module

**Convert-Pheno** is actually a Perl module who's name is `Convert::Pheno`. The module will be available in Comprehensive Perl Archive Network (CPAN) once the accompanying paper is accepted for publication.

The module can be used inside a `Perl` script, but also inside scripts from other languages (e.g., Python), as long as they allow for it. The operation is simple:

!!! Note "More ways of using `Convert-Pheno`"
    We have another ways of using the module (e.g., using an API), please take a look to the [API](use-as-an-api.md) documentation. 
    Remember, in the worst case scenario, one can always resort to using text files (e.g, `json`) with the command-line interface with `system` calls.

## Inside Perl

Find [here](https://github.com/mrueda/convert-pheno/blob/main/ex/perl.pl) an example script.


## Inside Python

Perl plays nicely with other languages and let users embed them into Perl's code (e.g., with `Inline`). Unfortunately, embedding Perl code into other languages is not as straightforward.

Luckily, the library [PyPerler](https://github.com/tkluck/pyperler) solves our problem. Once installed, one can use a code like the one below to access `Convert-Pheno` from Python.

Find [here](https://github.com/mrueda/convert-pheno/blob/main/ex/python.py) an example script.


!!! Warning "About PyPerler installation"
    Apart from [PypPerler](https://github.com/tkluck/pyperler#quick-install) itself, you may need to install `libperl-dev` to make it work.
    `sudo apt-get install libperl-dev`

## Other languages

It is possible to use Perl modules inside other languages. For **Ruby** you can use `ruby-perl` ([link](https://github.com/zephirworks/ruby-perl)) and for **Go** you can use [this library](https://github.com/bradfitz/campher).
