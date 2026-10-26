"""Turn raw readings (10-second Firestore docs, or the simulator's 1-minute rows)
into the regular 1-minute frame every other module uses.

Output frame: UTC DatetimeIndex at 1-minute steps, columns
  pigBodyTemp, ambientTemp, ambientHumidity, sprinkler (0/1), missing (bool), source
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from common import PIG, AMB, HUM, SPR, SENSORS, load_config
from sanity import apply_physical_limits


def fill_short_gaps(s: pd.Series, limit: int) -> pd.Series:
    """Linearly interpolate NaN runs of at most `limit` steps; longer runs stay NaN entirely."""
    isna = s.isna()
    if not isna.any():
        return s
    run_id = (isna != isna.shift()).cumsum()
    run_len = isna.groupby(run_id).transform("sum")
    interp = s.interpolate(method="linear", limit_area="inside")
    return s.where(~(isna & (run_len <= limit)), interp)


def sprinkler_minutes(index: pd.DatetimeIndex, logs: pd.DataFrame | None,
                      live_on: bool | None = None) -> pd.Series:
    """1 for every minute bin that overlaps a sprinkler run.

    `logs` has a UTC `timestamp` (run start) and `durationSec`, as in Firestore
    sprinkler_logs. A run still in progress is not logged yet, so `live_on`
    (live_sensor/latest.sprinkler) marks the newest minute.
    """
    out = pd.Series(0, index=index, dtype="int8", name=SPR)
    if logs is not None and len(logs) and len(index):
        # compare as int64 nanoseconds; pandas may hold the two sides at different resolutions
        starts = pd.to_datetime(logs["timestamp"], utc=True).dt.as_unit("ns")
        ends = starts + pd.to_timedelta(logs["durationSec"].astype(float), unit="s")
        bin_start = pd.DatetimeIndex(index).as_unit("ns").asi8
        bin_end = bin_start + pd.Timedelta("1min").value
        for s, e in zip(starts.dt.as_unit("ns").array.asi8, ends.dt.as_unit("ns").array.asi8):
            # minute bin [b, b+1min) overlaps run [s, e)
            out.iloc[(bin_start < e) & (bin_end > s)] = 1
    if live_on and len(index):
        out.iloc[-1] = 1
    return out


def to_minute_frame(raw: pd.DataFrame, cfg: dict | None = None, logs: pd.DataFrame | None = None,
                    live_on: bool | None = None, source: str = "real",
                    start: pd.Timestamp | None = None, end: pd.Timestamp | None = None) -> pd.DataFrame:
    """Resample to 1 minute (mean), interpolate gaps <= limit, flag longer gaps as missing.

    `raw` needs a `timestamp` column (or index) plus any of the sensor columns.
    If it already has a `sprinkler` column (simulator) that is used instead of `logs`.
    """
    cfg = cfg or load_config()
    limit = cfg["features"]["interpolate_limit_min"]
    df = raw.copy()
    if "timestamp" in df.columns:
        df = df.set_index("timestamp")
    df.index = pd.to_datetime(df.index, utc=True)
    df = df.sort_index()
    for v in SENSORS:
        if v not in df:
            df[v] = np.nan
    df, _ = apply_physical_limits(df, cfg)

    cols = SENSORS + ([SPR] if SPR in df else [])
    minute = df[cols].astype(float).resample(cfg["features"]["resample"]).mean()
    lo = start if start is not None else minute.index.min()
    hi = end if end is not None else minute.index.max()
    full = pd.date_range(lo.floor("min"), hi.floor("min"), freq="1min", tz="UTC", name="timestamp")
    minute = minute.reindex(full)

    for v in SENSORS:
        minute[v] = fill_short_gaps(minute[v], limit)
    if SPR in minute:
        minute[SPR] = (minute[SPR].fillna(0) > 0).astype("int8")
    else:
        minute[SPR] = sprinkler_minutes(minute.index, logs, live_on)
    minute["missing"] = minute[SENSORS].isna().any(axis=1)
    minute["source"] = source
    return minute
