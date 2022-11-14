#!/usr/bin/env python3
import pprint
import json
import pyperler

# Create interpreter
i = pyperler.Interpreter()

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

# Trick to serialize it back to Python dictionary
dictionary = json.loads((pprint.pformat(hashref)).replace("'", '"'))

# Using json.dumps to beautify
print(json.dumps(dictionary, indent=4, sort_keys=True))
