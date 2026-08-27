#!/usr/bin/env python3

import json
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
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(main.app)

    def test_health_and_catalog_are_served_by_perl(self):
        health = self.client.get("/api/health")
        self.assertEqual(health.status_code, 200, health.text)
        self.assertEqual(health.json()["data"]["engine"], "perl")

        catalog = self.client.get("/api/conversions")
        self.assertEqual(catalog.status_code, 200, catalog.text)
        self.assertEqual(catalog.json()["meta"]["count"], 17)

    def test_conversion_returns_serialized_artifacts(self):
        fixture = Path(__file__).resolve().parents[2] / "t" / "pxf2bff" / "in" / "pxf.json"
        payload = json.loads(fixture.read_text(encoding="utf-8"))
        response = self.client.post(
            "/api/conversions/pxf2bff",
            json={
                "input": {"data": payload},
                "output": {"entities": ["individuals", "biosamples"]},
                "options": {"test": True},
            },
        )
        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()
        self.assertEqual([item["filename"] for item in body["artifacts"]], ["individuals.json", "biosamples.json"])
        self.assertIsInstance(body["artifacts"][0]["content"], str)

    def test_error_statuses_match_the_shared_service(self):
        unknown = self.client.post("/api/conversions/nope", json={"input": {"data": {}}})
        self.assertEqual(unknown.status_code, 404)
        self.assertEqual(unknown.json()["error"]["code"], "unknown_conversion")

        invalid = self.client.post(
            "/api/conversions/pxf2bff",
            json={"input": {"data": {}}, "options": {"mapping_file": "/tmp/map.yaml"}},
        )
        self.assertEqual(invalid.status_code, 422)
        self.assertEqual(invalid.json()["error"]["code"], "invalid_request")

    def test_file_routes_are_not_advertised_by_the_reference_server(self):
        response = self.client.post("/api/conversions/csv2bff", json={})
        self.assertEqual(response.status_code, 422)
        self.assertEqual(response.json()["error"]["code"], "unsupported_transport")


if __name__ == "__main__":
    unittest.main()
