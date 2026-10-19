import json

import pytest

from fixtures import reading
from prism_ml.config import CONFIG_DIR
from prism_ml.features.contract import build_features, compute_thi, contract_hash, feature_names


def test_thi_formula_matches_published_expression():
    # (1.8*30+32) - (0.55-0.0055*80)*(1.8*30-26) = 86 - 0.11*28 = 82.92
    assert compute_thi(30, 80) == pytest.approx(82.92)


def test_features_follow_contract_order_and_names():
    contract = json.loads((CONFIG_DIR / "feature_contract_v1.json").read_text(encoding="utf-8"))
    assert feature_names() == [f["name"] for f in contract["features"]]
    assert list(build_features(reading())) == feature_names()


def test_thermal_summaries():
    px = [30.0] * 60 + [36.0, 37.0, 38.0, 39.0]
    f = build_features(reading(thermal_pixels_c=px, air_temp_c=31.0))
    assert f["thermal_max_c"] == 39.0
    assert f["thermal_top4_mean_c"] == pytest.approx(37.5)
    assert f["thermal_median_c"] == 30.0
    assert f["thermal_hot_minus_air_c"] == pytest.approx(6.5)


def test_features_deterministic_and_contract_hash_stable():
    r = reading()
    assert build_features(r) == build_features(r)
    assert contract_hash() == contract_hash() and len(contract_hash()) == 64


def test_no_water_level_feature():
    assert "water_level_pct" not in feature_names()
