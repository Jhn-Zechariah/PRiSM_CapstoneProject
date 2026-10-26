"""Sanity checks shared by the simulator tests, real-data ingestion and the API.

1. physical-limit check per sensor (out-of-spec readings become NaN = invalid)
2. range report: % of readings inside normal_band / observed_band / training_envelope
3. warning when too many real readings sit outside the training envelope
4. live-window check used by /predict to return "out_of_training_range"
"""
from __future__ import annotations

import warnings

import numpy as np
import pandas as pd

from common import SENSORS, bands, envelope, load_config


class OutsideEnvelopeWarning(UserWarning):
    pass


def apply_physical_limits(df: pd.DataFrame, cfg: dict | None = None) -> tuple[pd.DataFrame, dict]:
    """Return a copy with out-of-limit readings set to NaN, and the count per sensor."""
    cfg = cfg or load_config()
    out = df.copy()
    invalid = {}
    for var in SENSORS:
        if var not in out:
            continue
        lim = cfg["sanity"]["physical_limits"][var]
        col = pd.to_numeric(out[var], errors="coerce")
        bad = col.notna() & ((col < lim["min"]) | (col > lim["max"]))
        invalid[var] = int(bad.sum())
        out[var] = col.mask(bad)
    return out, invalid


def _pct_within(col: pd.Series, min: float, max: float) -> float:  # noqa: A002 (band keys)
    col = col.dropna()
    if col.empty:
        return float("nan")
    return round(100.0 * float(col.between(min, max).mean()), 2)


def range_report(df: pd.DataFrame, cfg: dict | None = None) -> dict:
    """Percentage of valid readings within each band, per sensor, plus all-sensor rows."""
    cfg = cfg or load_config()
    b = bands(cfg)
    rep = {"n_rows": int(len(df)), "per_sensor": {}}
    inside_all = pd.Series(True, index=df.index)
    complete = df[SENSORS].notna().all(axis=1)
    for var in SENSORS:
        col = df[var]
        rep["per_sensor"][var] = {
            "n_valid": int(col.notna().sum()),
            "pct_in_normal_band": _pct_within(col, **b["normal_band"][var]),
            "pct_in_observed_band": _pct_within(col, **b["observed_band"][var]),
            "pct_in_training_envelope": _pct_within(col, **b["training_envelope"][var]),
        }
        env = b["training_envelope"][var]
        inside_all &= col.between(env["min"], env["max"])
    n_complete = int(complete.sum())
    rep["pct_rows_all_sensors_in_envelope"] = (
        round(100.0 * float(inside_all[complete].mean()), 2) if n_complete else float("nan"))
    rep["outside_envelope_fraction"] = (
        round(1.0 - float(inside_all[complete].mean()), 4) if n_complete else float("nan"))
    rep["bands"] = b
    return rep


def envelope_warnings(report: dict, cfg: dict | None = None, emit: bool = True) -> list[str]:
    """Warn when the share of rows outside the training envelope exceeds the configured limit."""
    cfg = cfg or load_config()
    limit = cfg["sanity"]["max_outside_envelope_fraction"]
    frac = report.get("outside_envelope_fraction")
    msgs = []
    if frac is not None and not np.isnan(frac) and frac > limit:
        msgs.append(
            f"{frac:.1%} of readings are outside the training envelope (limit {limit:.0%}). "
            "The model would be extrapolating there and its predictions are unreliable.")
        for var, r in report["per_sensor"].items():
            if not np.isnan(r["pct_in_training_envelope"]) and r["pct_in_training_envelope"] < 100 * (1 - limit):
                msgs.append(f"  {var}: only {r['pct_in_training_envelope']}% inside the envelope")
    if emit:
        for m in msgs:
            warnings.warn(m, OutsideEnvelopeWarning, stacklevel=2)
    return msgs


def check_live_window(window: pd.DataFrame, cfg: dict | None = None, env: dict | None = None) -> dict:
    """Decide whether a live 1-minute window is inside the training envelope.

    Out of range when the latest complete reading is outside the envelope, or when
    more than `api_window_outside_fraction` of the window's rows are.
    """
    cfg = cfg or load_config()
    env = env or envelope(cfg)
    rows = window[SENSORS].dropna()
    if rows.empty:
        return {"outside": False, "fraction": float("nan"), "variables": []}
    outside = pd.DataFrame({v: ~rows[v].between(env[v]["min"], env[v]["max"]) for v in SENSORS})
    any_out = outside.any(axis=1)
    latest = outside.iloc[-1]
    frac = float(any_out.mean())
    is_out = bool(latest.any()) or frac > cfg["sanity"]["api_window_outside_fraction"]
    vars_out = [v for v in SENSORS if outside[v].any()]
    return {"outside": is_out, "fraction": round(frac, 4), "variables": vars_out}
