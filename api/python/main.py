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

import sys
from fastapi import Request, FastAPI
from pydantic import BaseModel, ValidationError
sys.path.append('../../lib/')
from convertpheno import PythonBinding

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

    # Creating object for class PythonBinding
    convert = PythonBinding(await request.json())

    # Run convert_pheno method
    return convert.convert_pheno()
