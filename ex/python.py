#!/usr/bin/env python3
import pprint
import json
import pyperler
import pathlib

def convert_pheno(json_data):

    # Create interpreter
    i = pyperler.Interpreter()

    ##############################
    # Only if the module WAS NOT #
    # installed from CPAN        #
    ##############################
    # We have to provide the path to <convert-pheno/lib>
    #i.use("lib '../lib'")
    bindir = pathlib.Path(__file__).resolve().parent
    lib_str = "lib '" + str(bindir) + "/../lib'"
    i.use(lib_str)

    # Load the module 
    CP = i.use('Convert::Pheno')

    # Create object
    convert = CP.new(json_data)

    #The result of the method (e.g. 'pxf2bff()') comes out as a scalar (Perl hashref)
    hashref=getattr(convert, json_data["method"])()

    # The data structure is accesible via pprint
    #pprint.pprint(hashref)

    # Trick to serialize it back to Python dictionary
    json_dict = json.loads((pprint.pformat(hashref)).replace("'", '"'))

    # return data as dict
    return json_dict

# Example PXF data
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

# Create data for convert_pheno
json_data = {
    "method" : "pxf2bff",
    "data" : my_pxf_json_data
}
     

# Using json.dumps to beautify
print(json.dumps(convert_pheno(json_data), indent=4, sort_keys=True))
