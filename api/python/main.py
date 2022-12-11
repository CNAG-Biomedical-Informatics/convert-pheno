#!/usr/bin/env python3
import pprint
import json
import pyperler
from fastapi import Request, FastAPI
from pydantic import BaseModel, ValidationError

def convert_pheno(json_data):

    # Create interpreter
    i = pyperler.Interpreter()

    ##############################
    # Only if the module WAS NOT #
    # installed from CPAN        #
    ##############################
    # We have to provide the path to <convert-pheno/lib>
    i.use("lib '../../lib'")

    # Load the module 
    CP = i.use('Convert::Pheno')

    # Create object
    convert = CP.new(json_data)

    # The result of the method (e.g. 'pxf2bff()') comes out as a scalar (Perl hashref)
    hashref=getattr(convert, json_data["method"])()

    # The data structure is accesible via pprint
    #pprint.pprint(hashref)

    # Trick to serialize it back to Python dictionary
    json_dict = json.loads((pprint.pformat(hashref)).replace("'", '"'))

    # return data as dict
    return json_dict

# Here we start the API
app = FastAPI()

class Item(BaseModel):
    method: str
    data: dict

@app.post(
    "/api",
    openapi_extra={
        "requestBody": {
            "content": {"application/json": {"schema": Item.schema()}},
            "required": True,
        },
    },
)

async def get_body(request: Request):
    return convert_pheno(await request.json())
