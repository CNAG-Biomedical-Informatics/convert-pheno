# As a Perl module

**Convert-Pheno** is actually a Perl module who's name is `Convert::Pheno`. The module will be available in Comprehensive Perl Archive Network (CPAN) once the accompanying paper is accepted for publication.

The module can be used inside a `Perl` script, but also inside scripts from other languages (e.g., Python), as long as they allow for it. The operation is simple:

!!! Note "More ways of using `Convert-Pheno`"
    We have another ways of using the module (e.g., using an API), please take a look to the [API](use-as-an-api.md) documentation. 
    Remember, in the worst case scenario, one can always resort to using text files (e.g, `json`) with the command-line interface with `system` calls.


## Inside Perl

Example (please see all options at CPAN):
```
#!/usr/bin/env perl

use Convert::Pheno;

# Define method
my $method = 'pfx2bff';

# Create object
my $convert = Convert::Pheno->new(
 {
     data => $my_pfx_json_data,
     method => $method
 }
);

# Run method and store result in hashref
my $hashref = $convert->$method;
...

```
## Inside Python

Perl plays nicely with other languages and let users embed them into Perl's code (e.g., with `Inline`). Unfortunately, embedding Perl code into other languages is not as straightforward.

One possible to solution that works is to use the library [PyPerler](https://github.com/tkluck/pyperler). Once installed, one can use a code like this to access `Convert-Pheno` from Python.

```
#!/usr/bin/env python3
import pyperler; i = pyperler.Interpreter()

# use a CPAN module (must be installed!!)
CP = i.use('Convert::Pheno')

method = 'pfx2bff'
convert = CP
(
    { 
        'method' method,
        'data' : my_pfx_json_data
    }
)
hashref = convert.method
 
```

!!! Warning "About PyPerler installation"
    Note you may need to install `libperl-dev` to make it work.
    
    `sudo apt-get install libperl-dev`

