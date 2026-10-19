"""Loads the JSON config files. Thresholds and field mappings live there, not in code."""
import hashlib
import json
from pathlib import Path

CONFIG_DIR = Path(__file__).resolve().parent.parent / "config"


def _load(name, path=None):
    p = Path(path) if path else CONFIG_DIR / name
    return json.loads(p.read_text(encoding="utf-8"))


def load_schema(path=None):
    return _load("sensor_schema.json", path)


def load_validation(path=None):
    return _load("validation.json", path)


def config_fingerprint(*configs):
    """Stable hash of the configs, so a dataset version changes when the rules change."""
    blob = json.dumps(configs, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(blob).hexdigest()
