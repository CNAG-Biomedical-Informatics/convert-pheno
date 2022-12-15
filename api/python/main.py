#!/usr/bin/env python3
#
#   A simple API to interact with Convert::Pheno
#
#   This file is part of Convert::Pheno
#
#   Last Modified: Dec/10/2022
#
#   $VERSION taken from Convert::Pheno
#
#   Copyright (C) 2022 Manuel Rueda (manuel.rueda@cnag.crg.eu)
#
#   License: Artistic License 2.0 

import pprint
import json
import pyperler
import pathlib
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
    #i.use("lib '../lib'")
    bindir = pathlib.Path(__file__).resolve().parent
    lib_str = "lib '" + str(bindir) + "/../../lib'"
    i.use(lib_str)

    # Load the module 
    CP = i.use('Convert::Pheno')

    # Create object
    convert = CP.new(json_data)

    #The result of the method (e.g. 'pxf2bff()') comes out as a scalar (Perl hashref)
    #type(hashref) = pyperler.ScalarValue
    hashref=getattr(convert, json_data["method"])()

    # Trick to serialize it back to a correct Python dictionary
    json_dict = json.loads((pprint.pformat(hashref)).replace("'", '"'))

    # Return dict
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
