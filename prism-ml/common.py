"""Shared helpers: config loading, paths, column names and the Firestore client.

Credentials (never written to disk, logged or printed):
  1. FIREBASE_CREDENTIALS_JSON  - service-account JSON *text* (Railway). Preferred.
  2. GOOGLE_APPLICATION_CREDENTIALS - path to a key file (local development, ADC).
"""
from __future__ import annotations

import json
import os
from functools import lru_cache
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent
CONFIG_PATH = Path(os.environ.get("PRISM_CONFIG", ROOT / "config.yaml"))
DATA_DIR = ROOT / "data"
SYNTHETIC_PATH = DATA_DIR / "synthetic" / "synthetic_1min.parquet"
REAL_DIR = DATA_DIR / "real"
REAL_PARTS_DIR = REAL_DIR / "readings_parts"
SPRINKLER_LOGS_PATH = REAL_DIR / "sprinkler_logs.parquet"
MODELS_DIR = ROOT / "models"
ARCHIVE_DIR = MODELS_DIR / "archive"
CURRENT_MODEL_PATH = MODELS_DIR / "current_model.joblib"
HOLDOUT_PATH = MODELS_DIR / "real_holdout.json"
REPORTS_DIR = ROOT / "reports"

# Firestore field names (written by the ESP32; do not rename)
PIG = "pigBodyTemp"
AMB = "ambientTemp"
HUM = "ambientHumidity"
SPR = "sprinkler"
SENSORS = [PIG, AMB, HUM]


@lru_cache(maxsize=None)
def _load(path: str) -> dict:
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def load_config(path: str | Path | None = None) -> dict:
    return _load(str(path or CONFIG_PATH))


def envelope(cfg: dict) -> dict:
    """training_envelope = union(normal_band, observed_band) widened by the configured margin."""
    out = {}
    for var in SENSORS:
        lo = min(cfg["normal_band"][var]["min"], cfg["observed_band"][var]["min"])
        hi = max(cfg["normal_band"][var]["max"], cfg["observed_band"][var]["max"])
        m = cfg["training_envelope"]["margin"][var]
        out[var] = {"min": round(lo - m["low"], 3), "max": round(hi + m["high"], 3)}
    return out


def bands(cfg: dict) -> dict:
    return {
        "normal_band": {v: {"min": cfg["normal_band"][v]["min"], "max": cfg["normal_band"][v]["max"]} for v in SENSORS},
        "observed_band": {v: dict(cfg["observed_band"][v]) for v in SENSORS},
        "training_envelope": envelope(cfg),
    }


def get_firestore_client():
    """Return a Cloud Firestore client, initialising firebase-admin once."""
    import firebase_admin
    from firebase_admin import credentials, firestore

    try:
        firebase_admin.get_app()
    except ValueError:
        raw = os.environ.get("FIREBASE_CREDENTIALS_JSON")
        if raw:
            try:
                info = json.loads(raw)
            except ValueError:
                # Never echo the variable's content
                raise RuntimeError("FIREBASE_CREDENTIALS_JSON is set but is not valid JSON") from None
            firebase_admin.initialize_app(credentials.Certificate(info))
        elif os.environ.get("GOOGLE_APPLICATION_CREDENTIALS"):
            firebase_admin.initialize_app()   # Application Default Credentials
        else:
            raise RuntimeError("No Firebase credentials: set FIREBASE_CREDENTIALS_JSON "
                               "or GOOGLE_APPLICATION_CREDENTIALS")
    return firestore.client()
