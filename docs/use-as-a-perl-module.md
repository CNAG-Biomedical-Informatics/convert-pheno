# As a Perl module

**Convert-Pheno** is actually a Perl module who's name is `Convert::Pheno`. The module will be available in Comprehensive Perl Archive Network (CPAN) once the accompanying paper is accepted for publication.

The module can be used inside a `Perl` script, but also inside scripts from other languages (e.g., Python), as long as they allow for it. The operation is simple:

!!! Note "More ways of using `Convert-Pheno`"
    We have another ways of using the module (e.g., using an API), please take a look to the [API](use-as-an-api.md) documentation. 
    Remember, in the worst case scenario, one can always resort to using text files (e.g, `json`) with the command-line interface with `system` calls.

## Inside Perl

Example (please see all options at [Convert::Pheno](https://metacpan.org/pod/Convert%3A%3APheno)):

```Perl
```
#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

##############################
# Only if the module WAS NOT #
# installed from CPAN        #
##############################
# - We have to provide the path to <convert-pheno/lib>
use lib '../lib';
use Convert::Pheno;

# Define method
my $method = 'pxf2bff';

# Define data
my $my_pxf_json_data = {
    "phenopacket" => {
        "id"      => "P0007500",
        "subject" => {
            "id"          => "P0007500",
            "dateOfBirth" => "unknown-01-01T00:00:00Z",
            "sex"         => "FEMALE"
        }
    }
  } ;

# Create object
my $convert = Convert::Pheno->new(
    {
        data   => $my_pxf_json_data,
        method => $method
    }
);

# Run method and store result in hashref
my $hashref = $convert->$method;
print Dumper $hashref;

```
## Inside Python

Perl plays nicely with other languages and let users embed them into Perl's code (e.g., with `Inline`). Unfortunately, embedding Perl code into other languages is not as straightforward.

Luckily, the library [PyPerler](https://github.com/tkluck/pyperler) solves our problem. Once installed, one can use a code like the one below to access `Convert-Pheno` from Python.

```Python
#!/usr/bin/env python3
import pprint
import json
import pyperler; i = pyperler.Interpreter()

##############################
# Only if the module WAS NOT #
# installed from CPAN        #
##############################
# - We have to provide the path to <convert-pheno/lib>
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

# The result of the method 'pxf2bff' comes out as a scalar (Perl hashref)
hashref=convert.pxf2bff()
#print(hashref)

# The data structure is accesible via pprint
#pprint.pprint(hashref)

# Trick to serialize it back to Python dictitonary
dictionary = json.loads((pprint.pformat(hashref)).replace("'", '"'))

# Using json.dumps to beautify
print(json.dumps(dictionary, indent=4, sort_keys=True))
```

!!! Warning "About PyPerler installation"
    Apart from [PypPerler](https://github.com/tkluck/pyperler#quick-install) itself, you may need to install `libperl-dev` to make it work.
    
    `sudo apt-get install libperl-dev`

## Other languages

It is possible to use Perl modules inside other languages. For **Ruby** you can use `ruby-perl` ([link](https://github.com/zephirworks/ruby-perl)) and for **Go** you can use [this library](https://github.com/bradfitz/campher).
