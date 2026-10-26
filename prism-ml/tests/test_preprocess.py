import numpy as np
import pandas as pd

from common import AMB, HUM, PIG
from preprocess import fill_short_gaps, sprinkler_minutes, to_minute_frame


def test_fill_short_gaps_only_short_runs():
    s = pd.Series([1.0, np.nan, np.nan, 4.0, np.nan, np.nan, np.nan, 8.0])
    out = fill_short_gaps(s, limit=2)
    assert out[:4].tolist() == [1.0, 2.0, 3.0, 4.0]
    assert out[4:7].isna().all()          # run of 3 > limit stays missing entirely


def test_resample_10s_to_minute_and_long_gap(cfg):
    ts = pd.date_range("2026-10-01 00:00", periods=6 * 20, freq="10s", tz="UTC")
    raw = pd.DataFrame({"timestamp": ts, PIG: 33.0, AMB: 28.0, HUM: 80.0})
    raw = raw[~((ts >= "2026-10-01 00:05") & (ts < "2026-10-01 00:12"))]   # 7-minute hole
    m = to_minute_frame(raw, cfg)
    assert len(m) == 20
    assert (m.index[1] - m.index[0]) == pd.Timedelta("1min")
    assert m["missing"].sum() == 7            # > 5 min: not interpolated
    assert m[PIG].iloc[0] == 33.0


def test_short_gap_is_interpolated(cfg):
    ts = pd.date_range("2026-10-01 00:00", periods=6 * 20, freq="10s", tz="UTC")
    raw = pd.DataFrame({"timestamp": ts, PIG: np.linspace(30, 32, len(ts)), AMB: 28.0, HUM: 80.0})
    raw = raw[~((ts >= "2026-10-01 00:05") & (ts < "2026-10-01 00:08"))]   # 3-minute hole
    m = to_minute_frame(raw, cfg)
    assert m["missing"].sum() == 0


def test_sprinkler_minutes_from_logs():
    idx = pd.date_range("2026-10-01 00:00", periods=10, freq="1min", tz="UTC")
    logs = pd.DataFrame({"timestamp": [pd.Timestamp("2026-10-01 00:02:30", tz="UTC")], "durationSec": [120]})
    s = sprinkler_minutes(idx, logs, live_on=True)
    assert s.tolist() == [0, 0, 1, 1, 1, 0, 0, 0, 0, 1]
