import json
import os
import pathlib
import re
import subprocess

__author__ = "Manuel Rueda"
__copyright__ = "Copyright 2022-2026, Manuel Rueda - CNAG"
__credits__ = ["None"]
__license__ = "Artistic License 2.0"
__maintainer__ = "Manuel Rueda"
__email__ = "manuel.rueda@cnag.eu"
__status__ = "Production"


def _load_project_version():
    lib_dir = pathlib.Path(__file__).resolve().parent
    perl_module = lib_dir / "Convert" / "Pheno.pm"
    try:
        source = perl_module.read_text(encoding="utf-8")
    except OSError:
        source = ""

    match = re.search(r"our\s+\$VERSION\s*=\s*['\"]([^'\"]+)['\"]", source)
    if match:
        return match.group(1)

    version_file = lib_dir.parent / "VERSION"
    try:
        version = version_file.read_text(encoding="utf-8").strip()
    except OSError as exc:
        raise RuntimeError(
            f"Could not determine Convert-Pheno version from {perl_module} or {version_file}"
        ) from exc
    if not version:
        raise RuntimeError(f"Convert-Pheno VERSION file is empty: {version_file}")
    return version


__version__ = _load_project_version()


class PythonBridgeError(RuntimeError):
    pass


def _load_public_conversions():
    registry_path = (
        pathlib.Path(__file__).resolve().parent.parent
        / "share"
        / "schema"
        / "public-conversions.json"
    )
    try:
        conversions = json.loads(registry_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(
            f"Could not load public conversion registry: {registry_path}"
        ) from exc
    if not isinstance(conversions, list) or not all(
        isinstance(item, str) for item in conversions
    ):
        raise RuntimeError(
            f"Public conversion registry must contain an array of strings: {registry_path}"
        )
    return frozenset(conversions)


PUBLIC_CONVERSIONS = _load_public_conversions()


def is_public_conversion(conversion):
    return isinstance(conversion, str) and conversion in PUBLIC_CONVERSIONS


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
        method = self.json.get("method") if isinstance(self.json, dict) else None
        if not is_public_conversion(method):
            raise PythonBridgeError(f"Unsupported conversion <{method}>")

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
