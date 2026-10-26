import numpy as np
import pandas as pd
import pytest

from common import AMB, HUM, PIG, SPR
from features import build_features, compute_thi, feature_columns, make_supervised, minutes_since_spray


def frame(n=180, seed=0):
    rng = np.random.default_rng(seed)
    idx = pd.date_range("2026-03-01", periods=n, freq="1min", tz="UTC")
    df = pd.DataFrame({PIG: 33 + rng.normal(0, 0.3, n).cumsum() * 0.1,
                       AMB: 28 + rng.normal(0, 0.2, n), HUM: 80 + rng.normal(0, 1, n),
                       SPR: (np.arange(n) % 60 < 3).astype(int)}, index=idx)
    df["missing"] = False
    df["source"] = "synthetic"
    return df


def test_thi_known_values():
    # (1.8*30+32) - (0.55-0.0055*80)*(1.8*30-26) = 86 - 0.11*28 = 82.92
    assert compute_thi(30, 80) == pytest.approx(82.92)
    # at 100 % RH the THI equals the Fahrenheit temperature
    assert compute_thi(25, 100) == pytest.approx(77.0)
    assert compute_thi(np.array([20, 30]), np.array([65, 80])).shape == (2,)


def test_thi_increases_with_temp_and_humidity():
    assert compute_thi(31, 80) > compute_thi(30, 80)
    assert compute_thi(30, 90) > compute_thi(30, 80)


def test_no_future_leakage(cfg):
    df = frame()
    t = 120
    base = build_features(df, cfg).iloc[t]
    changed = df.copy()
    changed.iloc[t + 1:, :3] += 50.0          # wildly change every future reading
    changed.iloc[t + 1:, 3] = 1
    after = build_features(changed, cfg).iloc[t]
    pd.testing.assert_series_equal(base, after)


def test_feature_columns_and_warmup(cfg):
    X = build_features(frame(), cfg)
    assert list(X.columns) == feature_columns(cfg)
    assert X.iloc[:30].isna().any(axis=1).all()       # lag-30 needs 30 minutes of history
    assert not X.iloc[31:].isna().any().any()


def test_targets_are_future_change(cfg):
    df = frame()
    sup = make_supervised(df, cfg)
    t = sup.index[0]
    assert sup.loc[t, "target_15"] == pytest.approx(df[PIG].shift(-15).loc[t] - df.loc[t, PIG])
    assert sup.loc[t, "actual_30"] == pytest.approx(df[PIG].shift(-30).loc[t])


def test_windows_overlapping_gaps_are_dropped(cfg):
    df = frame()
    df.loc[df.index[100:110], [PIG, AMB, HUM]] = np.nan
    df.loc[df.index[100:110], "missing"] = True
    sup = make_supervised(df, cfg)
    bad = (sup.index >= df.index[100 - 30]) & (sup.index <= df.index[109 + 30])
    assert not bad.any()


def test_minutes_since_spray():
    idx = pd.date_range("2026-03-01", periods=6, freq="1min", tz="UTC")
    s = pd.Series([0, 1, 0, 0, 0, 0], index=idx)
    assert minutes_since_spray(s, cap=240).tolist() == [240, 0, 1, 2, 3, 4]
    prior = idx[0] - pd.Timedelta(minutes=10)
    assert minutes_since_spray(s, cap=240, last_spray_before=prior).iloc[0] == 10
