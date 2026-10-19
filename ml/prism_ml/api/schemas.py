"""Versioned request/response schemas for API v1 (docs/API_REFERENCE.md)."""
from __future__ import annotations

from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator

from prism_ml.reading import SensorReading

ID_PATTERN = r"^[A-Za-z0-9_.:-]{1,64}$"
Num = Optional[float]


def _num(ge: float, le: float):
    # Wide sanity bounds only; physical sensor ranges are judged by the data-quality layer so that an
    # out-of-range value becomes "Sensor Check Required" instead of an opaque 422.
    return Field(default=None, ge=ge, le=le, allow_inf_nan=False)


class ReadingIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_version: Literal["1"] = "1"
    observed_at: datetime = Field(description="UTC timestamp of the reading (ISO-8601 with timezone)")
    air_temp_c: Num = _num(-100, 200)
    air_temp_valid: Optional[bool] = None
    relative_humidity_pct: Num = _num(-100, 200)
    humidity_valid: Optional[bool] = None
    thermal_pixels_c: Optional[list[float]] = Field(default=None, max_length=64)
    thermal_valid: Optional[bool] = None
    water_level_pct: Num = _num(-100, 200)
    water_valid: Optional[bool] = None
    calibration_profile: Optional[str] = Field(default=None, pattern=ID_PATTERN)
    device_id: Optional[str] = Field(default=None, pattern=ID_PATTERN)

    @field_validator("thermal_pixels_c")
    @classmethod
    def _pixels_finite(cls, v):
        if v is not None and any(p != p or p in (float("inf"), float("-inf")) or abs(p) > 1000 for p in v):
            raise ValueError("thermal pixels must be finite numbers")
        return v

    def to_reading(self) -> SensorReading:
        return SensorReading(
            observed_at=self.observed_at, air_temp_c=self.air_temp_c, air_temp_valid=self.air_temp_valid,
            relative_humidity_pct=self.relative_humidity_pct, humidity_valid=self.humidity_valid,
            thermal_pixels_c=self.thermal_pixels_c, thermal_valid=self.thermal_valid,
            water_level_pct=self.water_level_pct, water_valid=self.water_valid,
            calibration_profile=self.calibration_profile, device_id=self.device_id,
        )


class InsightOut(BaseModel):
    text: str
    kind: str
    references: list[str]


class ReferenceOut(BaseModel):
    id: str
    citation: str
    url: Optional[str]


class AssessmentOut(BaseModel):
    api_version: Literal["1"] = "1"
    status: str
    status_kind: Literal["thermal", "operational"]
    reason: Optional[str]
    observed_at: Optional[str]
    reading_age_seconds: Optional[float]
    measurements: dict
    data_quality: dict
    model: Optional[dict]
    confidence: Optional[float]
    probabilities: Optional[dict]
    details: dict
    insights: list[InsightOut]
    references: list[ReferenceOut]
    disclaimer: str
    feature_contract_version: str


class IngestOut(BaseModel):
    accepted: bool
    stored: bool
    reading_id: Optional[str]
    data_quality: dict


class ModelInfoOut(BaseModel):
    available: bool
    model: Optional[dict]
    reason: Optional[str]
    feature_contract_version: str
