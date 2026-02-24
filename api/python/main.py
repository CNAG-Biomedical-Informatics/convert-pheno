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
#   Copyright (C) 2022-2026 Manuel Rueda - CNAG (manuel.rueda@cnag.eu)
#
#   License: Artistic License 2.0

import sys
from fastapi import Request, FastAPI, HTTPException # MIT license
from pydantic import BaseModel, Field, parse_obj_as # MIT license
sys.path.append('../../lib/')
sys.path.append('local/lib/perl5')
from convertpheno import PythonBinding

# Here we start the API
app = FastAPI()


class Data(BaseModel):
    method: str = Field(...,title="Method")
    data: dict = Field(...,title="Data")
    ohdsi_db: bool = Field(False, title="OHDSI-DB")


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
