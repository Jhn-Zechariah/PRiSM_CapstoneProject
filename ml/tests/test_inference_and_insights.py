import json
import re
from datetime import datetime, timezone

import pytest

from fixtures import FIXTURE_CAL, frame, reading
from prism_ml.insights.references import REFERENCES
from prism_ml.models.inference import Assessor
from prism_ml.models.registry import ModelRegistry
from prism_ml.reading import (CLASSIFICATION_UNAVAILABLE, INSUFFICIENT_DATA, OPERATIONAL_STATUSES,
                              SENSOR_CHECK_REQUIRED, THERMAL_STATUSES, UNCERTAIN)

NOW = datetime(2026, 10, 12, 4, 0, tzinfo=timezone.utc)
BAD_INPUTS = [
    dict(air_temp_c=None), dict(thermal_valid=False), dict(thermal_pixels_c=[30.0] * 64), dict(humidity_valid=False),
    dict(observed_at=datetime(1970, 1, 1, tzinfo=timezone.utc)), dict(air_temp_c=float("nan")),
]


@pytest.fixture
def approved_assessor(trained_fixture_registry):
    reg, result, _ = trained_fixture_registry
    if not result.acceptance["passed"]:
        pytest.skip("fixture model did not pass acceptance")
    if reg.list_models()["approved"] != "fixture-model-a":
        reg.approve("fixture-model-a", approved_by="test-suite", note="synthetic fixture, tests only")
    return Assessor(reg)


def test_no_model_means_classification_unavailable(tmp_path):
    a = Assessor(ModelRegistry(tmp_path)).assess(reading(now=NOW), now=NOW)
    assert a.status == CLASSIFICATION_UNAVAILABLE and a.status_kind == "operational" and a.confidence is None


@pytest.mark.parametrize("kw", BAD_INPUTS)
def test_bad_data_never_produces_a_thermal_status(kw, tmp_path):
    a = Assessor(ModelRegistry(tmp_path)).assess(reading(now=NOW, **kw), now=NOW)
    assert a.status in (INSUFFICIENT_DATA, SENSOR_CHECK_REQUIRED)


@pytest.mark.parametrize("kw", BAD_INPUTS)
def test_bad_data_never_good_even_with_model(kw, approved_assessor):
    a = approved_assessor.assess(reading(now=NOW, **kw), now=NOW)
    assert a.status in (INSUFFICIENT_DATA, SENSOR_CHECK_REQUIRED) and a.status != "Good"


def test_stale_reading_with_model(approved_assessor):
    assert approved_assessor.assess(reading(age_s=600, now=NOW), now=NOW).status == INSUFFICIENT_DATA


def test_model_prediction_for_valid_reading(approved_assessor):
    r = reading(now=NOW, air_temp_c=26.0, relative_humidity_pct=75, thermal_pixels_c=frame(34.0, 25.0))
    a = approved_assessor.assess(r, now=NOW)
    assert a.status in THERMAL_STATUSES + (UNCERTAIN,)
    if a.status in THERMAL_STATUSES:
        assert a.status_kind == "thermal" and 0 < a.confidence <= 1
        assert abs(sum(a.probabilities.values()) - 1) < 1e-3


def test_outside_validated_range_is_uncertain(approved_assessor):
    r = reading(now=NOW, air_temp_c=45.0, thermal_pixels_c=frame(48.0, 44.0))
    a = approved_assessor.assess(r, now=NOW)
    assert a.status == UNCERTAIN and a.reason == "outside_validated_range" and "air_temp_c" in a.details["outside_features"]


def test_calibration_mismatch_with_model(approved_assessor):
    a = approved_assessor.assess(reading(now=NOW, calibration_profile="uncalibrated"), now=NOW)
    assert a.status == SENSOR_CHECK_REQUIRED and a.reason == "calibration_mismatch"


def test_contract_mismatch_disables_model(trained_fixture_registry, monkeypatch, approved_assessor):
    monkeypatch.setattr("prism_ml.models.inference.contract_hash", lambda: "different")
    a = Assessor(approved_assessor.registry)
    assert a.model is None and a.load_error
    assert a.assess(reading(now=NOW), now=NOW).status == CLASSIFICATION_UNAVAILABLE


def test_inference_error_is_contained(approved_assessor, monkeypatch):
    def boom(*_):
        raise RuntimeError("internal detail")
    monkeypatch.setattr(approved_assessor.model.estimator, "predict_proba", boom)
    a = approved_assessor.assess(reading(now=NOW), now=NOW)
    assert a.status == CLASSIFICATION_UNAVAILABLE and a.reason == "inference_error"
    assert "internal detail" not in json.dumps(a.as_dict(), default=str)


# ---------------------------------------------------------------- insights
DIAGNOSTIC = re.compile(r"\b(is sick|is healthy|has heat stroke|diagnosed|medication|antibiotic|dose)\b", re.I)


def _texts(a):
    return [i["text"] for i in a.insights]


@pytest.mark.parametrize("kw", [{}] + BAD_INPUTS)
def test_insights_for_operational_states(kw, tmp_path):
    a = Assessor(ModelRegistry(tmp_path)).assess(reading(now=NOW, **kw), now=NOW)
    texts = _texts(a)
    assert texts and all(t.strip().endswith((".", ")")) for t in texts)
    assert not any("favourable" in t for t in texts)
    assert not any(DIAGNOSTIC.search(t) for t in texts)


def test_every_reference_resolves(tmp_path):
    a = Assessor(ModelRegistry(tmp_path)).assess(reading(now=NOW, air_temp_c=33, relative_humidity_pct=85), now=NOW)
    for item in a.insights:
        for ref in item["references"]:
            assert ref in REFERENCES
    assert {r["id"] for r in a.references} == {ref for i in a.insights for ref in i["references"]}


def test_thi_context_only_above_reference_level(tmp_path):
    assessor = Assessor(ModelRegistry(tmp_path))
    hot = _texts(assessor.assess(reading(now=NOW, air_temp_c=33, relative_humidity_pct=85), now=NOW))
    mild = _texts(assessor.assess(reading(now=NOW, air_temp_c=25, relative_humidity_pct=60), now=NOW))
    assert any("THI" in t for t in hot) and not any("THI" in t for t in mild)


def test_low_water_sentence(tmp_path):
    texts = _texts(Assessor(ModelRegistry(tmp_path)).assess(reading(now=NOW, water_level_pct=10), now=NOW))
    assert any("water tank reads 10 %" in t for t in texts)


@pytest.mark.parametrize("status", THERMAL_STATUSES)
def test_thermal_status_sentences(status, tmp_path):
    from prism_ml.insights.engine import build_insights
    from prism_ml.models.inference import Assessment

    a = Assessment(status=status, status_kind="thermal", reason="model_prediction", observed_at=NOW,
                   reading_age_seconds=5, measurements={"air_temp_c": 30, "relative_humidity_pct": 70,
                                                        "thermal_max_c": 36, "water_level_pct": 80},
                   data_quality={"issues": []}, model=None, confidence=0.9)
    sentences, refs = build_insights(a, reading(now=NOW), metadata={})
    texts = [s["text"] for s in sentences]
    assert any("not a diagnosis" in t for t in texts)
    assert not any(DIAGNOSTIC.search(t) for t in texts)
    if status == "High Risk":
        assert any("veterinarian" in t for t in texts) and any("Assess the pigs now" in t for t in texts)
    if status == "Good":
        assert any("Continue monitoring" in t for t in texts)
    assert all(s["references"] or s["kind"] in ("status", "evidence") for s in sentences)


def test_operational_vocabulary_is_disjoint():
    assert not set(OPERATIONAL_STATUSES) & set(THERMAL_STATUSES)
