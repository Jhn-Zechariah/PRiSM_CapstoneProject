import numpy as np
import pytest

from common import AMB, HUM, PIG, SPR, bands
from sanity import range_report
from simulate import simulate


@pytest.fixture(scope="module")
def sim(cfg):
    return simulate(cfg, days=40, seed=123)


def test_schema(sim):
    for col in ["timestamp", PIG, AMB, HUM, SPR, "source"]:
        assert col in sim.columns
    assert (sim["source"] == "synthetic").all()
    assert str(sim["timestamp"].dt.tz) == "UTC"
    assert sim["timestamp"].diff().dropna().eq(np.timedelta64(60, "s")).all()
    assert set(sim[SPR].unique()) <= {0, 1}
    assert "label" not in sim.columns and "status" not in sim.columns      # no threshold labels
    assert len(sim) == 40 * 1440


def test_has_imperfections(sim):
    assert sim[PIG].isna().any()                     # missing gaps
    assert sim[SPR].sum() > 0                        # sprinkler events


def test_covers_normal_and_observed_bands(sim, cfg):
    b = bands(cfg)
    rep = range_report(sim, cfg)["per_sensor"]
    for var in (PIG, AMB, HUM):
        assert rep[var]["pct_in_normal_band"] >= 15, var
        assert rep[var]["pct_in_observed_band"] >= 30, var
        assert rep[var]["pct_in_training_envelope"] >= 98, var
        col = sim[var].dropna()
        # both edges of every band are represented: >= 0.25 % of readings in its lowest and highest quarter
        for band in ("normal_band", "observed_band"):
            lo, hi = b[band][var]["min"], b[band][var]["max"]
            q = 0.25 * (hi - lo)
            assert col.between(lo, lo + q).mean() >= 0.0025, (var, band, "low edge")
            assert col.between(hi - q, hi).mean() >= 0.0025, (var, band, "high edge")


def test_normal_scenario_follows_range_a(sim, cfg):
    cool = sim[sim["scenario"] == "cool_normal"]
    assert len(cool)
    for var in (PIG, AMB, HUM):
        nb = cfg["normal_band"][var]
        assert cool[var].between(nb["min"], nb["max"]).mean() >= 0.8, var


def test_reproducible(cfg):
    a = simulate(cfg, days=3, seed=5)
    b = simulate(cfg, days=3, seed=5)
    assert a.equals(b)
