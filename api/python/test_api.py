#!/usr/bin/env python3

import json
import os
import tempfile
import textwrap
import unittest
from pathlib import Path

try:
    from fastapi.testclient import TestClient
except ImportError as exc:  # pragma: no cover
    TestClient = None
    FASTAPI_IMPORT_ERROR = exc
else:
    FASTAPI_IMPORT_ERROR = None

import main


@unittest.skipIf(TestClient is None, f"fastapi test client unavailable: {FASTAPI_IMPORT_ERROR}")
class PythonApiTests(unittest.TestCase):
    def setUp(self):
        self.original_bridge = os.environ.get("CONVERT_PHENO_PERL_BRIDGE")

    def tearDown(self):
        if self.original_bridge is None:
            os.environ.pop("CONVERT_PHENO_PERL_BRIDGE", None)
        else:
            os.environ["CONVERT_PHENO_PERL_BRIDGE"] = self.original_bridge

    def test_api_preserves_allowed_payload_fields(self):
        with tempfile.TemporaryDirectory() as tempdir:
            script_path = Path(tempdir) / "echo_bridge.pl"
            script_path.write_text(
                textwrap.dedent(
                    """\
                    use strict;
                    use warnings;
                    local $/;
                    my $raw = <STDIN>;
                    print $raw;
                    """
                ),
                encoding="utf-8",
            )
            os.environ["CONVERT_PHENO_PERL_BRIDGE"] = str(script_path)

            client = TestClient(main.app)
            payload = {
                "conversion": "pxf2bff",
                "input": {
                    "data": {},
                },
                "output": {
                    "entities": ["individuals", "biosamples"],
                },
                "options": {
                    "ohdsi_db": False,
                },
            }

            response = client.post("/api", json=payload)

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json(),
            {
                "ok": True,
                "data": {
                    "data": {},
                    "entities": ["individuals", "biosamples"],
                    "ohdsi_db": False,
                    "method": "pxf2bff",
                },
                "meta": {"conversion": "pxf2bff"},
            },
        )

    def test_api_accepts_self_contained_fhir_route(self):
        with tempfile.TemporaryDirectory() as tempdir:
            script_path = Path(tempdir) / "echo_bridge.pl"
            script_path.write_text(
                textwrap.dedent(
                    """\
                    use strict;
                    use warnings;
                    local $/;
                    my $raw = <STDIN>;
                    print $raw;
                    """
                ),
                encoding="utf-8",
            )
            os.environ["CONVERT_PHENO_PERL_BRIDGE"] = str(script_path)

            client = TestClient(main.app)
            response = client.post(
                "/api",
                json={
                    "conversion": "fhir2bff",
                    "input": {
                        "data": {
                            "resourceType": "Bundle",
                            "type": "collection",
                            "entry": [],
                        }
                    },
                },
            )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["data"]["method"], "fhir2bff")

    def test_api_accepts_table_oriented_omop_data(self):
        request_path = Path(__file__).resolve().parents[1] / "perl" / "omop.json"
        payload = json.loads(request_path.read_text(encoding="utf-8"))

        client = TestClient(main.app)
        response = client.post("/api", json=payload)

        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["data"][0]["id"], "974")

    def test_api_returns_structured_error_for_invalid_request(self):
        client = TestClient(main.app)
        response = client.post("/api", json={"conversion": "pxf2bff"})

        self.assertEqual(response.status_code, 422)
        body = response.json()
        self.assertEqual(body["ok"], False)
        self.assertEqual(body["error"]["code"], "invalid_request")

    def test_api_rejects_filesystem_options(self):
        client = TestClient(main.app)
        response = client.post(
            "/api",
            json={
                "conversion": "pxf2bff",
                "input": {"data": {}},
                "options": {"out_file": "/tmp/result.json"},
            },
        )

        self.assertEqual(response.status_code, 422)
        body = response.json()
        self.assertEqual(body["error"]["code"], "invalid_request")
        self.assertIn("Unsupported key 'out_file'", body["error"]["message"])

    def test_api_rejects_keys_in_the_wrong_section(self):
        client = TestClient(main.app)
        response = client.post(
            "/api",
            json={
                "conversion": "pxf2bff",
                "input": {"entities": ["individuals"]},
            },
        )

        self.assertEqual(response.status_code, 422)
        body = response.json()
        self.assertEqual(body["ok"], False)
        self.assertEqual(body["error"]["code"], "invalid_request")
        self.assertIn("Unsupported key 'entities' in 'input'", body["error"]["message"])

    def test_api_rejects_callable_internal_method(self):
        client = TestClient(main.app)
        response = client.post(
            "/api",
            json={"conversion": "get_info", "input": {}},
        )

        self.assertEqual(response.status_code, 422)
        body = response.json()
        self.assertEqual(body["ok"], False)
        self.assertEqual(body["error"]["code"], "conversion_error")
        self.assertIn("Unsupported conversion <get_info>", body["error"]["message"])

    def test_api_rejects_file_based_conversion_routes(self):
        client = TestClient(main.app)
        response = client.post(
            "/api",
            json={"conversion": "redcap2bff", "input": {"data": {}}},
        )

        self.assertEqual(response.status_code, 422)
        body = response.json()
        self.assertEqual(body["error"]["code"], "conversion_error")
        self.assertIn("not available over HTTP", body["error"]["message"])


if __name__ == "__main__":
    unittest.main()
