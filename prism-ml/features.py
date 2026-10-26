"""Feature engineering on the 1-minute frame (see preprocess.py).

Every feature at time t uses only readings at or before t (lags shift forward,
rolling windows look backward), so nothing from the future leaks in.
Targets are the change in pigBodyTemp from t to t+h, for h in horizons_min.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from common import PIG, AMB, HUM, SPR, load_config


def compute_thi(temp_c, rh_pct):
    """Temperature-Humidity Index (NRC 1971 form, as reviewed by Vermeer & Aarnink for pigs):

        THI = (1.8*T + 32) - (0.55 - 0.0055*RH) * (1.8*T - 26)

    T = air temperature in deg C (DHT22), RH = relative humidity in % (DHT22).
    The result is on the Fahrenheit-like THI scale. Used only as an input
    feature - never as a label.
    """
    t = np.asarray(temp_c, dtype=float)
    rh = np.asarray(rh_pct, dtype=float)
    thi = (1.8 * t + 32.0) - (0.55 - 0.0055 * rh) * (1.8 * t - 26.0)
    return thi if thi.ndim else float(thi)


def max_lookback(cfg: dict) -> int:
    f = cfg["features"]
    return max(max(f["lags_min"]), max(f["rolling_windows_min"]))


def feature_columns(cfg: dict | None = None) -> list[str]:
    cfg = cfg or load_config()
    f = cfg["features"]
    cols = [PIG, AMB, HUM, "thi", "gap"]
    for v in (PIG, AMB, HUM):
        cols += [f"{v}_lag{k}" for k in f["lags_min"]]
    for v in (PIG, AMB, HUM, "thi"):
        for w in f["rolling_windows_min"]:
            cols += [f"{v}_mean{w}", f"{v}_max{w}", f"{v}_roc{w}"]
    cols += ["tod_sin", "tod_cos", SPR, "min_since_spray"]
    return cols


def minutes_since_spray(spr: pd.Series, cap: int, last_spray_before: pd.Timestamp | None = None) -> pd.Series:
    """Minutes since the sprinkler was last ON (0 while it is on), capped at `cap`."""
    t = pd.Series(spr.index, index=spr.index)
    last_on = t.where(spr > 0).ffill()
    if last_spray_before is not None:
        last_on = last_on.fillna(pd.Timestamp(last_spray_before).tz_convert("UTC"))
    mins = (t - last_on).dt.total_seconds() / 60.0
    return mins.clip(lower=0, upper=cap).fillna(cap)


def build_features(frame: pd.DataFrame, cfg: dict | None = None,
                   last_spray_before: pd.Timestamp | None = None) -> pd.DataFrame:
    """Features for every row of ONE contiguous 1-minute frame."""
    cfg = cfg or load_config()
    f = cfg["features"]
    X = pd.DataFrame(index=frame.index)
    X[PIG], X[AMB], X[HUM] = frame[PIG], frame[AMB], frame[HUM]
    X["thi"] = compute_thi(frame[AMB], frame[HUM])
    X["gap"] = frame[PIG] - frame[AMB]
    for v in (PIG, AMB, HUM):
        for k in f["lags_min"]:
            X[f"{v}_lag{k}"] = X[v].shift(k)
    for v in (PIG, AMB, HUM, "thi"):
        for w in f["rolling_windows_min"]:
            roll = X[v].rolling(w + 1, min_periods=w + 1)   # t-w .. t inclusive
            X[f"{v}_mean{w}"] = roll.mean()
            X[f"{v}_max{w}"] = roll.max()
            X[f"{v}_roc{w}"] = (X[v] - X[v].shift(w)) / w   # C (or %, THI) per minute
    local = frame.index.tz_convert(cfg["project"]["timezone"])
    hours = local.hour + local.minute / 60.0
    X["tod_sin"] = np.sin(2 * np.pi * hours / 24.0)
    X["tod_cos"] = np.cos(2 * np.pi * hours / 24.0)
    X[SPR] = frame[SPR].astype(float)
    X["min_since_spray"] = minutes_since_spray(frame[SPR], f["minutes_since_spray_cap"], last_spray_before)
    return X[feature_columns(cfg)]


def make_supervised(frame: pd.DataFrame, cfg: dict | None = None) -> pd.DataFrame:
    """Features + targets for one contiguous frame.

    Rows are dropped when their window [t - lookback, t + max horizon] overlaps a
    long gap (`missing`), or when any feature/target is NaN.
    Columns added: target_<h> (pigBodyTemp change t -> t+h), actual_<h> (pigBodyTemp at t+h),
    plus source.
    """
    cfg = cfg or load_config()
    horizons = cfg["features"]["horizons_min"]
    back, fwd = max_lookback(cfg), max(horizons)
    X = build_features(frame, cfg)
    miss = frame["missing"].astype(float)
    # any missing minute in [t-back, t]  or in [t, t+fwd]
    past_gap = miss.rolling(back + 1, min_periods=1).max() > 0
    future_gap = miss[::-1].rolling(fwd + 1, min_periods=1).max()[::-1] > 0
    for h in horizons:
        X[f"actual_{h}"] = frame[PIG].shift(-h)
        X[f"target_{h}"] = X[f"actual_{h}"] - frame[PIG]
    X["source"] = frame["source"]
    X = X[~(past_gap | future_gap)]
    return X.dropna()
