import json
import os
import pathlib
import subprocess

__author__ = "Manuel Rueda"
__copyright__ = "Copyright 2022-2026, Manuel Rueda - CNAG"
__credits__ = ["None"]
__license__ = "Artistic License 2.0"
__version__ = "0.30_1"
__maintainer__ = "Manuel Rueda"
__email__ = "manuel.rueda@cnag.eu"
__status__ = "Production"


class PythonBridgeError(RuntimeError):
    pass


class PythonBinding:

    def __init__(self, payload):
        self.json = payload

    def _repo_root(self):
        return pathlib.Path(__file__).resolve().parent.parent

    def _bridge_path(self):
        bridge_override = os.environ.get("CONVERT_PHENO_PERL_BRIDGE")
        if bridge_override:
            return pathlib.Path(bridge_override).expanduser().resolve()
        return self._repo_root() / "api" / "perl" / "json_bridge.pl"

    def _perl_bin(self):
        return os.environ.get("CONVERT_PHENO_PERL_BIN", "perl")

    def convert_pheno(self):
        bridge = self._bridge_path()
        if not bridge.is_file():
            raise PythonBridgeError(f"Perl bridge not found: {bridge}")

        try:
            payload_json = json.dumps(self.json)
        except (TypeError, ValueError) as exc:
            raise PythonBridgeError(f"Could not serialize payload to JSON: {exc}") from exc

        try:
            completed = subprocess.run(
                [self._perl_bin(), str(bridge)],
                capture_output=True,
                check=False,
                cwd=self._repo_root(),
                input=payload_json,
                text=True,
            )
        except OSError as exc:
            raise PythonBridgeError(f"Failed to run Perl bridge: {exc}") from exc

        if completed.returncode != 0:
            stderr = completed.stderr.strip()
            message = stderr or f"Perl bridge exited with status {completed.returncode}"
            raise PythonBridgeError(message)

        stdout = completed.stdout.strip()
        if not stdout:
            raise PythonBridgeError("Perl bridge returned no JSON output")

        try:
            return json.loads(stdout)
        except json.JSONDecodeError as exc:
            stderr = completed.stderr.strip()
            detail = f"Invalid JSON from Perl bridge: {stdout[:200]!r}"
            if stderr:
                detail += f" (stderr: {stderr})"
            raise PythonBridgeError(detail) from exc
