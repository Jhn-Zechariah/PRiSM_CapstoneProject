"""Map a forecast pigBodyTemp to Good / Needs Attention / High Risk.

Presentation only: the model is a regressor and the cutoffs live in config.yaml
(the ones above the normal band are placeholders awaiting calibration).
"""
from __future__ import annotations

import numpy as np

from common import load_config

LEVELS = ["Good", "Needs Attention", "High Risk"]


def risk_level(temp_c: float, cfg: dict | None = None) -> str:
    r = (cfg or load_config())["risk"]
    if temp_c >= r["high_risk_at"]:
        return "High Risk"
    if temp_c > r["needs_attention_above"]:
        return "Needs Attention"
    return "Good"


def risk_levels(temps, cfg: dict | None = None) -> np.ndarray:
    r = (cfg or load_config())["risk"]
    t = np.asarray(temps, dtype=float)
    out = np.full(t.shape, "Good", dtype=object)
    out[t > r["needs_attention_above"]] = "Needs Attention"
    out[t >= r["high_risk_at"]] = "High Risk"
    return out


def recommendation(level: str, sprinkler_on: bool = False, cfg: dict | None = None) -> str:
    rec = (cfg or load_config())["risk"]["recommendations"]
    text = rec[level]
    if sprinkler_on:
        text += rec["sprinkler_on_suffix"]
    return text
