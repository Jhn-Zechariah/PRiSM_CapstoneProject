"""Feature construction shared by training and inference (feature contract v1).

Only call :func:`build_features` on readings that passed :func:`prism_ml.data.quality.check_reading`.
"""
from __future__ import annotations

import hashlib
import json
from functools import lru_cache

import numpy as np

from prism_ml.config import load_config
from prism_ml.reading import SensorReading


@lru_cache(maxsize=1)
def contract() -> dict:
    return load_config("feature_contract_v1")


def feature_names() -> list[str]:
    return [f["name"] for f in contract()["features"]]


def contract_version() -> str:
    return contract()["contract_version"]


def contract_hash() -> str:
    """Stable hash of the contract file contents, stored with every model to detect contract drift."""
    payload = json.dumps(contract(), sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def compute_thi(air_temp_c: float, rh_pct: float) -> float:
    """THI = (1.8*T+32) - (0.55-0.0055*RH)*(1.8*T-26), Vermeer & Aarnink (2023) p.8."""
    return (1.8 * air_temp_c + 32.0) - (0.55 - 0.0055 * rh_pct) * (1.8 * air_temp_c - 26.0)


def build_features(reading: SensorReading) -> dict[str, float]:
    pixels = np.asarray(reading.thermal_pixels_c, dtype=float)
    t = float(reading.air_temp_c)
    rh = float(reading.relative_humidity_pct)
    top4 = float(np.sort(pixels)[-4:].mean())
    feats = {
        "air_temp_c": t,
        "relative_humidity_pct": rh,
        "thi": compute_thi(t, rh),
        "thermal_max_c": float(pixels.max()),
        "thermal_top4_mean_c": top4,
        "thermal_median_c": float(np.median(pixels)),
        "thermal_std_c": float(pixels.std()),
        "thermal_hot_minus_air_c": top4 - t,
    }
    # Guard against the contract and this function drifting apart.
    if list(feats) != feature_names():
        raise RuntimeError("build_features() is out of sync with configs/feature_contract_v1.json")
    return feats
