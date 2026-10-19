"""Data-quality and availability layer.

Explicit integrity rules decide whether a reading may be passed to the classifier at all. They exist so
that missing, stale, malformed or faulty sensor data can never silently produce a reassuring "Good".
They are NOT a thermal-status classifier: the only statuses they can emit are operational ones
(``Insufficient Data`` / ``Sensor Check Required``).

The same checks run during training (without the freshness check) so that the model is only ever
trained on readings that would have been accepted at inference time.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

from prism_ml.config import load_config
from prism_ml.reading import INSUFFICIENT_DATA, SENSOR_CHECK_REQUIRED, SensorReading


@dataclass(frozen=True)
class Issue:
    code: str
    field: str
    message: str
    severity: str  # "missing" -> Insufficient Data, "fault" -> Sensor Check Required, "info" -> no block


@dataclass
class QualityReport:
    issues: list[Issue] = field(default_factory=list)
    reading_age_seconds: Optional[float] = None

    @property
    def blocking(self) -> list[Issue]:
        return [i for i in self.issues if i.severity in ("missing", "fault")]

    @property
    def ok(self) -> bool:
        return not self.blocking

    @property
    def operational_status(self) -> Optional[str]:
        """Sensor faults take precedence over missing data because they need a physical check."""
        if any(i.severity == "fault" for i in self.issues):
            return SENSOR_CHECK_REQUIRED
        if any(i.severity == "missing" for i in self.issues):
            return INSUFFICIENT_DATA
        return None

    def as_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "operational_status": self.operational_status,
            "reading_age_seconds": self.reading_age_seconds,
            "issues": [i.__dict__ for i in self.issues],
        }


def _finite(x: Any) -> bool:
    return isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(float(x))


def _check_scalar(report: QualityReport, reading: SensorReading, name: str, flag: str, lo: float, hi: float,
                  label: str) -> None:
    value = getattr(reading, name)
    valid = getattr(reading, flag)
    if value is None:
        report.issues.append(Issue("missing_value", name, f"No {label} reading was received.", "missing"))
        return
    if valid is False:
        report.issues.append(Issue("sensor_flag_invalid", name, f"The device marked the {label} reading as invalid.", "fault"))
        return
    if valid is None:
        report.issues.append(Issue("validity_flag_missing", name, f"The {label} reading has no validity flag from the device.", "missing"))
        return
    if not _finite(value):
        report.issues.append(Issue("not_a_number", name, f"The {label} reading is not a valid number.", "fault"))
        return
    if not lo <= float(value) <= hi:
        report.issues.append(Issue("outside_sensor_range", name,
                                   f"The {label} reading ({value}) is outside the sensor's measurable range ({lo} to {hi}).",
                                   "fault"))


def _check_thermal(report: QualityReport, reading: SensorReading, contract: dict, rules: dict) -> None:
    spec = contract["reading_fields"]["thermal_pixels_c"]
    pixels = reading.thermal_pixels_c
    n = rules["thermal_pixel_count"]
    if pixels is None:
        report.issues.append(Issue("missing_value", "thermal_pixels_c", "No thermal camera frame was received.", "missing"))
        return
    if reading.thermal_valid is False:
        report.issues.append(Issue("sensor_flag_invalid", "thermal_pixels_c",
                                   "The device marked the thermal camera frame as invalid.", "fault"))
        return
    if reading.thermal_valid is None:
        report.issues.append(Issue("validity_flag_missing", "thermal_pixels_c",
                                   "The thermal camera frame has no validity flag from the device.", "missing"))
        return
    if len(pixels) != n:
        report.issues.append(Issue("wrong_pixel_count", "thermal_pixels_c",
                                   f"The thermal frame has {len(pixels)} values instead of {n}.", "fault"))
        return
    lo, hi = spec["sensor_range"]
    marker = spec["invalid_marker"]
    bad = [p for p in pixels if not _finite(p) or float(p) == marker or not lo <= float(p) <= hi]
    if bad:
        report.issues.append(Issue("invalid_pixels", "thermal_pixels_c",
                                   f"{len(bad)} of {n} thermal pixels are missing or outside the sensor range.", "fault"))
        return
    mean = sum(float(p) for p in pixels) / n
    std = math.sqrt(sum((float(p) - mean) ** 2 for p in pixels) / n)
    if std < rules["thermal_min_std_c"]:
        report.issues.append(Issue("flat_frame", "thermal_pixels_c",
                                   "All thermal pixels read the same value, which suggests a covered, disconnected or frozen sensor.",
                                   "fault"))


def check_reading(reading: SensorReading, now: Optional[datetime] = None, check_freshness: bool = True,
                  allowed_calibration_profiles: Optional[list[str]] = None) -> QualityReport:
    contract = load_config("feature_contract_v1")
    rules = load_config("data_quality")
    fields = contract["reading_fields"]
    report = QualityReport()

    # --- timestamp -------------------------------------------------------------------------------
    ts = reading.observed_at
    if ts is None:
        report.issues.append(Issue("missing_timestamp", "observed_at", "The reading has no timestamp.", "missing"))
    elif ts.tzinfo is None:
        report.issues.append(Issue("naive_timestamp", "observed_at", "The reading timestamp has no timezone.", "missing"))
    elif ts.year < rules["min_valid_epoch_year"]:
        report.issues.append(Issue("clock_not_synced", "observed_at",
                                   "The device clock was not synchronised when this reading was taken (timestamp is invalid).",
                                   "fault"))
    elif check_freshness:
        now = now or datetime.now(timezone.utc)
        age = (now - ts).total_seconds()
        report.reading_age_seconds = round(age, 1)
        if age > rules["max_reading_age_seconds"]:
            report.issues.append(Issue("stale_reading", "observed_at",
                                       f"The latest reading is {int(age)} seconds old, so it may not reflect current conditions.",
                                       "missing"))
        elif age < -rules["max_future_skew_seconds"]:
            report.issues.append(Issue("future_timestamp", "observed_at",
                                       "The reading timestamp is in the future; the device clock may be wrong.", "fault"))

    # --- scalar sensors --------------------------------------------------------------------------
    at = fields["air_temp_c"]
    _check_scalar(report, reading, "air_temp_c", "air_temp_valid", *at["sensor_range"], label="air temperature")
    rh = fields["relative_humidity_pct"]
    _check_scalar(report, reading, "relative_humidity_pct", "humidity_valid", *rh["sensor_range"], label="humidity")

    # --- thermal array ---------------------------------------------------------------------------
    _check_thermal(report, reading, contract, rules)

    # --- calibration -----------------------------------------------------------------------------
    if allowed_calibration_profiles:
        if reading.calibration_profile not in allowed_calibration_profiles:
            report.issues.append(Issue("calibration_mismatch", "calibration_profile",
                                       "The device's sensor calibration profile differs from the one the model was trained with.",
                                       "fault"))

    # --- water level (operational only: never blocks classification) -----------------------------
    if reading.water_level_pct is not None and reading.water_valid is False:
        report.issues.append(Issue("water_sensor_invalid", "water_level_pct",
                                   "The water-level sensor reading is invalid; check the tank level by hand.", "info"))
    return report
