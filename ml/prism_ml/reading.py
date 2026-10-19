"""Framework-independent representation of one PRISM sensor reading (feature contract v1 field names)."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional, Sequence

# Status vocabulary. The three thermal-status classes can ONLY come from an approved, trained model.
THERMAL_STATUSES = ("Good", "Needs Attention", "High Risk")
# Operational states describe the system, never the pigs.
INSUFFICIENT_DATA = "Insufficient Data"
SENSOR_CHECK_REQUIRED = "Sensor Check Required"
CLASSIFICATION_UNAVAILABLE = "Classification Unavailable"
UNCERTAIN = "Uncertain"
OPERATIONAL_STATUSES = (INSUFFICIENT_DATA, SENSOR_CHECK_REQUIRED, CLASSIFICATION_UNAVAILABLE, UNCERTAIN)


@dataclass(frozen=True)
class SensorReading:
    observed_at: Optional[datetime]
    air_temp_c: Optional[float] = None
    air_temp_valid: Optional[bool] = None
    relative_humidity_pct: Optional[float] = None
    humidity_valid: Optional[bool] = None
    thermal_pixels_c: Optional[Sequence[float]] = None
    thermal_valid: Optional[bool] = None
    water_level_pct: Optional[float] = None
    water_valid: Optional[bool] = None
    calibration_profile: Optional[str] = None
    device_id: Optional[str] = None
    extra: dict = field(default_factory=dict)
