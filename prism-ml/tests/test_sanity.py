import warnings

import pandas as pd
import pytest

from common import AMB, HUM, PIG, envelope
from sanity import OutsideEnvelopeWarning, apply_physical_limits, check_live_window, envelope_warnings, range_report


def test_physical_limits_mark_invalid(cfg):
    df = pd.DataFrame({PIG: [33.0, 90.0, -5.0], AMB: [28.0, 28.0, 100.0], HUM: [80.0, 101.0, -1.0]})
    out, bad = apply_physical_limits(df, cfg)
    assert bad == {PIG: 2, AMB: 1, HUM: 2}
    assert out[PIG].isna().tolist() == [False, True, True]
    assert out[HUM].isna().tolist() == [False, True, True]


def test_envelope_is_union_plus_margin(cfg):
    env = envelope(cfg)
    m = cfg["training_envelope"]["margin"]
    assert env[AMB]["min"] == pytest.approx(cfg["normal_band"][AMB]["min"] - m[AMB]["low"])
    assert env[AMB]["max"] == pytest.approx(cfg["observed_band"][AMB]["max"] + m[AMB]["high"])
    assert env[PIG]["min"] == pytest.approx(cfg["observed_band"][PIG]["min"] - m[PIG]["low"])
    assert env[PIG]["max"] == pytest.approx(cfg["normal_band"][PIG]["max"] + m[PIG]["high"])


def test_range_report_percentages(cfg):
    df = pd.DataFrame({PIG: [35.0, 30.0, 36.0, 50.0], AMB: [20.0, 28.0, 30.0, 29.0],
                       HUM: [65.0, 80.0, 90.0, 85.0]})
    rep = range_report(df, cfg)["per_sensor"]
    assert rep[PIG]["pct_in_normal_band"] == 50.0          # 35, 36
    assert rep[PIG]["pct_in_observed_band"] == 50.0        # 30, 35
    assert rep[PIG]["pct_in_training_envelope"] == 75.0    # 50 is outside
    assert rep[AMB]["pct_in_normal_band"] == 25.0


def test_warning_when_too_many_outside(cfg):
    n = 100
    df = pd.DataFrame({PIG: [33.0] * n, AMB: [28.0] * n, HUM: [80.0] * n})
    df.loc[:9, AMB] = 45.0          # 10 % outside > 5 % limit
    rep = range_report(df, cfg)
    with pytest.warns(OutsideEnvelopeWarning):
        msgs = envelope_warnings(rep, cfg)
    assert msgs
    ok = range_report(df.assign(**{AMB: 28.0}), cfg)
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        assert envelope_warnings(ok, cfg) == []


def test_live_window_check(cfg):
    inside = pd.DataFrame({PIG: [33.0] * 40, AMB: [28.0] * 40, HUM: [80.0] * 40})
    assert not check_live_window(inside, cfg)["outside"]
    latest_out = inside.copy()
    latest_out.loc[39, AMB] = 40.0
    res = check_live_window(latest_out, cfg)
    assert res["outside"] and res["variables"] == [AMB]
    many_out = inside.copy()
    many_out.loc[:9, HUM] = 20.0      # 25 % of window, latest reading fine
    assert check_live_window(many_out, cfg)["outside"]
