#!/usr/bin/env python3
import pprint
import json
import pyperler
from fastapi import Request, FastAPI

def convert_pheno(json_data):
    
    # Create interpreter
    i = pyperler.Interpreter()
    
    # We have to provide the path to <convert-pheno/lib>
    i.use("lib '../../lib'") 
    
    # Load the module 
    CP = i.use('Convert::Pheno')
    
    # Create object
    convert = CP.new(json_data)
    
    # The result of the method 'pxf2bff' comes out as a scalar (Perl hashref)
    hashref=convert.pxf2bff()
    
    # Trick to serialize it back to Python dictionary
    dictionary = json.loads((pprint.pformat(hashref)).replace("'", '"'))
    
    # return 
    return dictionary

# Here we start the API
app = FastAPI()

@app.post("/api")

async def get_body(request: Request):
    return json.dumps(convert_pheno(await request.json()))
