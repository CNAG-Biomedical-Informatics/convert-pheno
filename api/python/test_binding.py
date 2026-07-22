#!/usr/bin/env python3

import os
import re
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))

import convertpheno
from convertpheno import PythonBinding, PythonBridgeError


class PythonBindingTests(unittest.TestCase):
    def test_python_version_tracks_perl_and_release_versions(self):
        perl_source = (
            Path(convertpheno.__file__).resolve().parent / "Convert" / "Pheno.pm"
        ).read_text(encoding="utf-8")
        match = re.search(
            r"our\s+\$VERSION\s*=\s*['\"]([^'\"]+)['\"]",
            perl_source,
        )
        self.assertIsNotNone(match)
        self.assertEqual(convertpheno.__version__, match.group(1))

        release_version = (
            Path(convertpheno.__file__).resolve().parent.parent / "VERSION"
        ).read_text(encoding="utf-8").strip()
        self.assertEqual(convertpheno.__version__.split("_", 1)[0], release_version)

    def test_binding_rejects_callable_internal_method(self):
        binding = PythonBinding({"method": "get_info"})
        with self.assertRaisesRegex(
            PythonBridgeError,
            r"Unsupported conversion <get_info>",
        ):
            binding.convert_pheno()

    def setUp(self):
        self.original_bridge = os.environ.get("CONVERT_PHENO_PERL_BRIDGE")

    def tearDown(self):
        if self.original_bridge is None:
            os.environ.pop("CONVERT_PHENO_PERL_BRIDGE", None)
        else:
            os.environ["CONVERT_PHENO_PERL_BRIDGE"] = self.original_bridge

    def test_convert_pheno_success(self):
        result = PythonBinding(
            {
                "method": "pxf2bff",
                "data": {
                    "phenopacket": {
                        "id": "P0007500",
                        "subject": {
                            "id": "P0007500",
                            "dateOfBirth": "unknown-01-01T00:00:00Z",
                            "sex": "FEMALE",
                        },
                    }
                },
            }
        ).convert_pheno()

        self.assertEqual(result["id"], "P0007500")

    def test_convert_pheno_reports_bridge_failure(self):
        with self.assertRaises(PythonBridgeError):
            PythonBinding({"data": {}}).convert_pheno()

    def test_convert_pheno_reports_invalid_bridge_json(self):
        with tempfile.TemporaryDirectory() as tempdir:
            script_path = Path(tempdir) / "bad_bridge.pl"
            script_path.write_text(
                textwrap.dedent(
                    """\
                    print "not-json";
                    """
                ),
                encoding="utf-8",
            )
            os.environ["CONVERT_PHENO_PERL_BRIDGE"] = str(script_path)

            with self.assertRaises(PythonBridgeError) as ctx:
                PythonBinding({"method": "pxf2bff", "data": {}}).convert_pheno()

        self.assertIn("Invalid JSON from Perl bridge", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
