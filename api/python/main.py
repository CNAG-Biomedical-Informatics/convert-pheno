#!/usr/bin/env python3
#
#   A simple API to interact with Convert::Pheno
#
#   This file is part of Convert::Pheno
#
#   Last Modified: Dec/27/2022
#
#   $VERSION taken from Convert::Pheno
#
#   Copyright (C) 2022 Manuel Rueda - CNAG (manuel.rueda@cnag.crg.eu)
#
#   License: Artistic License 2.0

import sys
from fastapi import Request, FastAPI, HTTPException
from pydantic import BaseModel, parse_obj_as
sys.path.append('../../lib/')
from convertpheno import PythonBinding

# Here we start the API
app = FastAPI()


class Data(BaseModel):
    method: str
    data: dict


@app.post(
    "/api",
    openapi_extra={
        "requestBody": {
            "content": {"application/json": {"schema": Data.schema()}},
            "required": True,
        },
    },
)
async def get_body(request: Request):

    # Receive and validate payload JSON
    payload = parse_obj_as(Data, await request.json())

    # Creating object for class PythonBinding
    convert = PythonBinding(dict(payload))

    # Run convert_pheno method
    return convert.convert_pheno()
