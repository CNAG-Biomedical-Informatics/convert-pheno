#!/usr/bin/env python3

from pathlib import Path
import sys

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

LIB_DIR = Path(__file__).resolve().parents[2] / "lib"
sys.path.insert(0, str(LIB_DIR))

from convertpheno import (
    CONVERSION_REGISTRY,
    PythonBridgeError,
    ServiceBridge,
    __version__,
    conversion_spec,
    is_public_conversion,
)

app = FastAPI(
    title="Convert-Pheno artifact API",
    version=__version__,
    description="An HTTP wrapper around the Perl conversion engine.",
)

def bridge_response(result):
    if result.get("ok") is False:
        error = result.get("error", {})
        status = int(error.pop("status", 500))
        return JSONResponse(status_code=status, content=result)
    return result


def bridge_failure(exc):
    return JSONResponse(
        status_code=500,
        content={
            "ok": False,
            "error": {
                "code": "infrastructure_error",
                "message": str(exc),
            },
        },
    )


@app.get("/api/health")
def api_health():
    try:
        return bridge_response(ServiceBridge({}).call("health"))
    except PythonBridgeError as exc:
        return bridge_failure(exc)


@app.get("/api/conversions")
def api_conversions():
    try:
        result = ServiceBridge({}).call("catalog")
        result["data"] = [
            route for route in result.get("data", []) if "json" in route["input"]["transports"]
        ]
        result.setdefault("meta", {})["count"] = len(result["data"])
        return bridge_response(result)
    except PythonBridgeError as exc:
        return bridge_failure(exc)


@app.post("/api/conversions/{conversion}")
async def api_conversion(conversion: str, request: Request):
    if is_public_conversion(conversion):
        spec = conversion_spec(conversion)
        source = spec["source"]
        transports = CONVERSION_REGISTRY.get("input_definitions", {}).get(source, {}).get(
            "transports", ["json"]
        )
        if "json" not in transports:
            return JSONResponse(
                status_code=422,
                content={
                    "ok": False,
                    "error": {
                        "code": "unsupported_transport",
                        "message": "This reference FastAPI server accepts JSON routes only; use the Mojolicious API or workbench for file uploads",
                    },
                    "meta": {"conversion": conversion},
                },
            )

    try:
        payload = await request.json()
    except Exception:
        return JSONResponse(
            status_code=422,
            content={
                "ok": False,
                "error": {
                    "code": "invalid_request",
                    "message": "Request body must contain valid JSON",
                },
                "meta": {"conversion": conversion},
            },
        )
    try:
        result = ServiceBridge({}).call("execute", conversion, payload)
        if result.get("ok") is False:
            result.setdefault("meta", {"conversion": conversion})
        return bridge_response(result)
    except PythonBridgeError as exc:
        return bridge_failure(exc)
