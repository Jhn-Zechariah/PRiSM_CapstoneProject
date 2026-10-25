"""API settings from config/api.json plus the bounds it borrows from validation.json."""
import json
from functools import lru_cache
from pathlib import Path

from pipeline.config import load_validation

ROOT = Path(__file__).resolve().parent.parent


@lru_cache(maxsize=1)
def api_config():
    return json.loads((ROOT / "config" / "api.json").read_text(encoding="utf-8"))


def impossible(channel):
    """(lo, hi) physical/spec range for a sensor channel, from config/validation.json."""
    return tuple(load_validation()["channels"][channel]["impossible"])


def max_future_s():
    return load_validation()["timestamp"]["max_future_s"]


def registry_path():
    p = Path(api_config()["registry"]["path"])
    return p if p.is_absolute() else ROOT / p


def exports_path():
    p = Path(api_config()["retrain"]["exports_dir"])
    return p if p.is_absolute() else ROOT / p
