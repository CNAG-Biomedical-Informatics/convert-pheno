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

from pathlib import Path
import sys
from fastapi import Request, FastAPI
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, ValidationError, parse_obj_as

LIB_DIR = Path(__file__).resolve().parents[2] / "lib"
sys.path.append(str(LIB_DIR))

from convertpheno import PythonBinding, PythonBridgeError

# Here we start the API
app = FastAPI()


class Data(BaseModel):
    conversion: str = Field(..., title="Conversion")
    input: dict = Field(..., title="Input")
    output: dict = Field(default_factory=dict, title="Output")
    options: dict = Field(default_factory=dict, title="Options")

    class Config:
        extra = "forbid"


def api_error(status_code, code, message, method=None, details=None):
    content = {
        "ok": False,
        "error": {
            "code": code,
            "message": message,
        },
    }
    if details is not None:
        content["error"]["details"] = details
    if method is not None:
        content["meta"] = {"conversion": method}
    return JSONResponse(status_code=status_code, content=content)


def is_bridge_runtime_error(message):
    prefixes = (
        "Perl bridge not found:",
        "Failed to run Perl bridge:",
        "Perl bridge returned no JSON output",
        "Invalid JSON from Perl bridge:",
    )
    return message.startswith(prefixes)


def flatten_public_request(payload):
    conversion = payload.conversion
    convert_payload = {}

    for section_name, section in (
        ("input", payload.input),
        ("output", payload.output),
        ("options", payload.options),
    ):
        if "method" in section:
            raise ValueError(f"Reserved key 'method' is not allowed in '{section_name}'")

        overlap = set(convert_payload).intersection(section)
        if overlap:
            key = sorted(overlap)[0]
            raise ValueError(
                f"Duplicate key '{key}' appears in more than one of input/output/options"
            )

        convert_payload.update(section)

    convert_payload["method"] = conversion
    return conversion, convert_payload


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
    raw_payload = await request.json()
    try:
        if hasattr(Data, "model_validate"):
            payload = Data.model_validate(raw_payload)
        else:
            payload = parse_obj_as(Data, raw_payload)
    except ValidationError as exc:
        return api_error(
            422,
            "invalid_request",
            "Request body does not match the API schema",
            details=exc.errors(),
        )

    try:
        conversion, convert_payload = flatten_public_request(payload)
    except ValueError as exc:
        return api_error(422, "invalid_request", str(exc))

    # Creating object for class PythonBinding
    convert = PythonBinding(convert_payload)

    # Run convert_pheno method
    try:
        result = convert.convert_pheno()
    except PythonBridgeError as exc:
        status_code = 500 if is_bridge_runtime_error(str(exc)) else 422
        code = "bridge_error" if status_code == 500 else "conversion_error"
        return api_error(status_code, code, str(exc), method=conversion)

    return {
        "ok": True,
        "data": result,
        "meta": {
            "conversion": conversion,
        },
    }
