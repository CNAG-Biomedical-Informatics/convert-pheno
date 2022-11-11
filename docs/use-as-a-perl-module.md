# As a Perl module

**Convert-Pheno** is actually a Perl module who's name is `Convert::Pheno`. The module will be available in Comprehensive Perl Archive Network (CPAN) once the accompanying paper is accepted for publication.

The module can be used inside a `Perl` script, but also inside scripts from other languages (e.g., Python), as long as they allow for it. The operation is simple:

!!! Note "More ways of using `Convert-Pheno`"
    We have another ways of using the module (e.g., using an API), please take a look to the [API](use-as-an-api.md) documentation. 
    Remember, in the worst case scenario, one can always resort to using text files (e.g, `json`) with the command-line interface with `system` calls.


## Inside Perl

Example (please see all options at [Convert::Pheno](https://metacpan.org/pod/Convert%3A%3APheno):

!!! Warning "About @INC errors"
    If you are not downloading `Convert:.Pheno` from CPAN you may have to add its path to @INC, like this:
    export PERL5LIB=your_path_to/convert-pheno/lib

```Perl
#!/usr/bin/env perl

use Convert::Pheno;

# Define method
my $method = 'pxf2bff';

# Create object
my $convert = Convert::Pheno->new(
 {
     data => $my_pxf_json_data,
     method => $method
 }
);

# Run method and store result in hashref
my $hashref = $convert->$method;
...

```
## Inside Python

Perl plays nicely with other languages and let users embed them into Perl's code (e.g., with `Inline`). Unfortunately, embedding Perl code into other languages is not as straightforward.

Luckily, the library [PyPerler](https://github.com/tkluck/pyperler) solves our problem. Once installed, one can use a code like the one below to access `Convert-Pheno` from Python.

```Python
#!/usr/bin/env python3
from pprint import pprint
import pyperler; i = pyperler.Interpreter()

##############################
# Only if the module WAS NOT #
# installed with CPAN        #
##############################
# - We have to provide the path to <convert-pheno/lib>
# - Here we're running from inside ex/
i.use("lib '../lib'") 

# Load the module 
CP = i.use('Convert::Pheno')

# Example data
my_pxf_json_data = {
    "phenopacket": {
    "id": "P0007500",
    "subject": {
      "id": "P0007500",
      "dateOfBirth": "unknown-01-01T00:00:00Z",
      "sex": "FEMALE"
    }
  }
}

# Create object
convert = CP.new (
    {
        "method" : "pxf2bff",
        "data" : my_pxf_json_data
    }
)

# Pretty print
pprint(convert.pxf2bff())
```

!!! Warning "About PyPerler installation"
    Apart from [PypPerler](https://github.com/tkluck/pyperler#quick-install) itself, you may need to install `libperl-dev` to make it work.
    
    `sudo apt-get install libperl-dev`
