"""Locations of the ML project's directories and loaders for the JSON configs in ``configs/``."""
from __future__ import annotations

import json
import os
from functools import lru_cache
from pathlib import Path
from typing import Any

ML_ROOT = Path(__file__).resolve().parent.parent
CONFIG_DIR = ML_ROOT / "configs"
DATA_DIR = ML_ROOT / "data"
RAW_EXTERNAL_DIR = DATA_DIR / "raw" / "external"
RAW_LOCAL_DIR = DATA_DIR / "raw" / "local"
INTERIM_DIR = DATA_DIR / "interim"
PROCESSED_DIR = DATA_DIR / "processed"
METADATA_DIR = DATA_DIR / "metadata"
REPORTS_DIR = ML_ROOT / "reports"


def artifacts_dir() -> Path:
    """Model registry root. Overridable so tests and deployments can point elsewhere."""
    return Path(os.environ.get("PRISM_ARTIFACTS_DIR", ML_ROOT / "artifacts"))


@lru_cache(maxsize=None)
def load_config(name: str) -> dict[str, Any]:
    path = CONFIG_DIR / f"{name}.json"
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)
