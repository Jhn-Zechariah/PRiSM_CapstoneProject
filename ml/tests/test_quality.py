from datetime import datetime, timedelta, timezone

import pytest

from fixtures import frame, reading
from prism_ml.data.quality import check_reading
from prism_ml.reading import INSUFFICIENT_DATA, SENSOR_CHECK_REQUIRED

NOW = datetime(2026, 10, 12, 4, 0, tzinfo=timezone.utc)


def codes(report):
    return {i.code for i in report.issues}


def test_valid_reading_passes():
    r = check_reading(reading(now=NOW), now=NOW)
    assert r.ok and r.operational_status is None and r.reading_age_seconds == 5


@pytest.mark.parametrize("field", ["air_temp_c", "relative_humidity_pct", "thermal_pixels_c"])
def test_missing_value_is_insufficient_data(field):
    r = check_reading(reading(now=NOW, **{field: None}), now=NOW)
    assert not r.ok and r.operational_status == INSUFFICIENT_DATA and "missing_value" in codes(r)


def test_missing_validity_flag_is_insufficient():
    r = check_reading(reading(now=NOW, air_temp_valid=None), now=NOW)
    assert r.operational_status == INSUFFICIENT_DATA and "validity_flag_missing" in codes(r)


def test_device_invalid_flag_requires_sensor_check():
    r = check_reading(reading(now=NOW, humidity_valid=False), now=NOW)
    assert r.operational_status == SENSOR_CHECK_REQUIRED


def test_stale_reading():
    r = check_reading(reading(age_s=121, now=NOW), now=NOW)
    assert r.operational_status == INSUFFICIENT_DATA and "stale_reading" in codes(r)


def test_future_timestamp():
    r = check_reading(reading(age_s=-120, now=NOW), now=NOW)
    assert r.operational_status == SENSOR_CHECK_REQUIRED and "future_timestamp" in codes(r)


def test_unsynced_clock_1970():
    r = check_reading(reading(now=NOW, observed_at=datetime(1970, 1, 1, tzinfo=timezone.utc)), now=NOW)
    assert "clock_not_synced" in codes(r) and not r.ok


def test_naive_timestamp_rejected():
    r = check_reading(reading(now=NOW, observed_at=datetime(2026, 10, 12, 3, 59)), now=NOW)
    assert "naive_timestamp" in codes(r)


@pytest.mark.parametrize("kw,code", [
    ({"air_temp_c": 95.0}, "outside_sensor_range"),
    ({"relative_humidity_pct": 104.0}, "outside_sensor_range"),
    ({"air_temp_c": float("nan")}, "not_a_number"),
    ({"thermal_pixels_c": frame(35, 29)[:63]}, "wrong_pixel_count"),
    ({"thermal_pixels_c": [0.0] + frame(35, 29)[1:]}, "invalid_pixels"),
    ({"thermal_pixels_c": [85.0] + frame(35, 29)[1:]}, "invalid_pixels"),
    ({"thermal_pixels_c": [30.0] * 64}, "flat_frame"),
])
def test_sensor_faults(kw, code):
    r = check_reading(reading(now=NOW, **kw), now=NOW)
    assert r.operational_status == SENSOR_CHECK_REQUIRED and code in codes(r)


def test_fault_takes_precedence_over_missing():
    r = check_reading(reading(now=NOW, air_temp_c=None, thermal_valid=False), now=NOW)
    assert r.operational_status == SENSOR_CHECK_REQUIRED


def test_water_sensor_problem_does_not_block():
    r = check_reading(reading(now=NOW, water_valid=False), now=NOW)
    assert r.ok and "water_sensor_invalid" in codes(r)


def test_calibration_mismatch():
    r = check_reading(reading(now=NOW, calibration_profile="other"), now=NOW, allowed_calibration_profiles=["fixture-cal-1"])
    assert r.operational_status == SENSOR_CHECK_REQUIRED and "calibration_mismatch" in codes(r)


def test_training_mode_skips_freshness():
    r = check_reading(reading(age_s=10_000, now=NOW), now=NOW, check_freshness=False)
    assert r.ok
