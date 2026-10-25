"""Feature/target frame for one horizon. Features use only data available at time t.

No identifiers (pen, device, record id) are features. The target is the MEASURED value
at t + horizon; rows without a measured target, current value or same-time-yesterday
value are dropped so every model and baseline is scored on exactly the same rows.
"""
import math

import numpy as np
import pandas as pd

from forecast.data import TARGET_COLUMN

VAR_COLUMN = {"dht_temp_c": "temp", "dht_humidity_pct": "hum", "thi": "thi"}


def _steps(minutes, step, what):
    if minutes % step:
        raise ValueError(f"{what}={minutes} min is not a multiple of resample_minutes={step}")
    return minutes // step


def lookback_minutes(fcfg):
    """How far back the features reach (used by serving to require enough history)."""
    f = fcfg["features"]
    return max(f["lags_minutes"] + f["rate_of_change_minutes"] + f["rolling_windows_minutes"]
               + ([f["misting_window_minutes"]] if f["misting"] else []))


def feature_block(g, fcfg, misting):
    """Features for one pen's sorted regular grid. Shared by training and serving."""
    step, f, tz = fcfg["resample_minutes"], fcfg["features"], fcfg["timezone"]
    F = {}
    for var in f["variables"]:
        x = g[VAR_COLUMN[var]]
        F[f"{var}_now"] = x
        for lag in f["lags_minutes"]:
            F[f"{var}_lag{lag}m"] = x.shift(_steps(lag, step, "lag"))
        for r in f["rate_of_change_minutes"]:
            F[f"{var}_rate{r}m_per_h"] = (x - x.shift(_steps(r, step, "rate"))) / r * 60.0
        for w in f["rolling_windows_minutes"]:
            roll = x.rolling(_steps(w, step, "window"), min_periods=1)
            for stat in f["rolling_stats"]:
                F[f"{var}_roll{w}m_{stat}"] = getattr(roll, stat)()
    local = g["time"].dt.tz_convert(tz)
    if f["time_of_day"]:
        frac = (local.dt.hour + local.dt.minute / 60.0) / 24.0
        F["tod_sin"] = np.sin(2 * math.pi * frac)
        F["tod_cos"] = np.cos(2 * math.pi * frac)
    if misting:
        mw = _steps(f["misting_window_minutes"], step, "misting window")
        F["mist_on_now"] = g["mist_on"]
        F[f"mist_on_frac_{f['misting_window_minutes']}m"] = g["mist_on"].rolling(mw, min_periods=1).mean()
        F["mist_active_s_now"] = g["mist_active_s"]
    return pd.DataFrame(F), local


def build_frame(grid, fcfg, horizon):
    step, f = fcfg["resample_minutes"], fcfg["features"]
    h = _steps(horizon, step, "horizon")
    day = _steps(1440, step, "day")
    if h >= day:
        raise ValueError("horizon must be shorter than 24 h for the same-time-yesterday baseline")
    tz, target = fcfg["timezone"], TARGET_COLUMN[fcfg["target"]]
    misting = f["misting"] and grid["mist_on"].notna().any()
    frames, feature_names = [], None

    for pen, g in grid.groupby("pen", sort=True):
        g = g.sort_values("time").reset_index(drop=True)
        out, local = feature_block(g, fcfg, misting)
        feature_names = list(out.columns)

        s = g[target]
        out["pen"] = pen
        out["time"] = g["time"]
        out["local_date"] = local.dt.date.astype(str)
        out["local_hour"] = local.dt.hour
        out["target_local_hour"] = (g["time"] + pd.Timedelta(minutes=horizon)).dt.tz_convert(tz).dt.hour
        out["current"] = s
        out["y_level"] = s.shift(-h)
        out["yday"] = s.shift(day - h)                     # measured value at t + h - 24 h
        out["fut_max"] = pd.concat([s.shift(-k) for k in range(1, h + 1)], axis=1).max(axis=1, skipna=True)
        lb = _steps(fcfg["error_analysis"]["fault_lookback_minutes"], step, "fault lookback")
        out["fault_recent"] = g["n_fault"].rolling(lb, min_periods=1).sum() > 0
        out["mist_now"] = g["mist_on"]
        out["temp_now"], out["hum_now"] = g["temp"], g["hum"]
        frames.append(out)

    df = pd.concat(frames, ignore_index=True)
    df = df[df["y_level"].notna() & df["current"].notna() & df["yday"].notna()].reset_index(drop=True)
    df["y"] = df["y_level"] - df["current"] if fcfg["predict"] == "delta" else df["y_level"]
    return df, feature_names
