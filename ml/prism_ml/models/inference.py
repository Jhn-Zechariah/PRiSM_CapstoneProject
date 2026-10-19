"""Inference: data-quality gate -> feature contract -> approved model -> abstention -> insights.

Order of decisions (each step can stop the pipeline with an operational status):

1. Data-quality layer           -> "Sensor Check Required" / "Insufficient Data"
2. No approved model available  -> "Classification Unavailable"
3. Calibration-profile mismatch -> "Sensor Check Required"
4. Inputs outside the model's validated feature ranges -> "Uncertain"
5. Max class probability below the validated abstention threshold -> "Uncertain"
6. Otherwise the model's class: "Good" / "Needs Attention" / "High Risk"
"""
from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

import numpy as np
import pandas as pd

from prism_ml.data.quality import check_reading
from prism_ml.features.contract import build_features, contract_hash, contract_version, feature_names
from prism_ml.insights.engine import build_insights
from prism_ml.models.registry import LoadedModel, ModelRegistry, RegistryError
from prism_ml.reading import CLASSIFICATION_UNAVAILABLE, SENSOR_CHECK_REQUIRED, UNCERTAIN, SensorReading

log = logging.getLogger("prism_ml.inference")

DISCLAIMER = ("PRISM is a monitoring aid. It does not diagnose disease or heat stroke and does not replace "
              "assessment by a veterinarian.")


@dataclass
class Assessment:
    status: str
    status_kind: str                  # "thermal" (from the trained model) or "operational"
    reason: Optional[str]
    observed_at: Optional[datetime]
    reading_age_seconds: Optional[float]
    measurements: dict
    data_quality: dict
    model: Optional[dict]
    confidence: Optional[float] = None
    probabilities: Optional[dict] = None
    details: dict = field(default_factory=dict)
    insights: list = field(default_factory=list)
    references: list = field(default_factory=list)
    disclaimer: str = DISCLAIMER

    def as_dict(self) -> dict[str, Any]:
        d = self.__dict__.copy()
        d["observed_at"] = self.observed_at.isoformat() if self.observed_at else None
        d["feature_contract_version"] = contract_version()
        return d


def _measurements(reading: SensorReading) -> dict:
    px = reading.thermal_pixels_c
    finite_px = [float(p) for p in px if isinstance(p, (int, float)) and np.isfinite(p) and p != 0.0] if px else []
    return {
        "air_temp_c": reading.air_temp_c if reading.air_temp_valid else None,
        "relative_humidity_pct": reading.relative_humidity_pct if reading.humidity_valid else None,
        "thermal_max_c": max(finite_px) if finite_px and reading.thermal_valid else None,
        "water_level_pct": reading.water_level_pct if reading.water_valid else None,
    }


class Assessor:
    def __init__(self, registry: Optional[ModelRegistry] = None):
        self.registry = registry or ModelRegistry()
        self.model: Optional[LoadedModel] = None
        self.load_error: Optional[str] = None
        self.reload()

    def reload(self) -> None:
        try:
            self.model = self.registry.load_approved()
            self.load_error = None
            if self.model and self.model.metadata.get("feature_contract_sha256") != contract_hash():
                self.load_error = "approved model was trained with a different feature contract"
                log.error("Model %s rejected: feature contract mismatch", self.model.model_id)
                self.model = None
        except (RegistryError, OSError, ValueError) as exc:  # integrity failure, unreadable file ...
            log.exception("Approved model could not be loaded")
            self.model, self.load_error = None, type(exc).__name__

    def model_info(self) -> Optional[dict]:
        if not self.model:
            return None
        md = self.model.metadata
        return {"model_id": self.model.model_id, "algorithm": md["algorithm"],
                "feature_contract_version": md["feature_contract_version"], "created_at": md["created_at"],
                "abstention_threshold": md["abstention_threshold"]}

    def _result(self, reading, report, status, kind, reason, **kw) -> Assessment:
        a = Assessment(status=status, status_kind=kind, reason=reason, observed_at=reading.observed_at,
                       reading_age_seconds=report.reading_age_seconds, measurements=_measurements(reading),
                       data_quality=report.as_dict(), model=self.model_info(), **kw)
        a.insights, a.references = build_insights(a, reading, self.model.metadata if self.model else None)
        return a

    def assess(self, reading: SensorReading, now: Optional[datetime] = None) -> Assessment:
        now = now or datetime.now(timezone.utc)
        allowed = self.model.metadata.get("calibration_profiles") if self.model else None
        report = check_reading(reading, now=now)
        if not report.ok:
            return self._result(reading, report, report.operational_status, "operational", "data_quality")
        if self.model is None:
            return self._result(reading, report, CLASSIFICATION_UNAVAILABLE, "operational",
                                "model_load_failed" if self.load_error else "no_approved_model")
        if allowed:
            cal = check_reading(reading, now=now, allowed_calibration_profiles=allowed)
            if not cal.ok:
                return self._result(reading, cal, SENSOR_CHECK_REQUIRED, "operational", "calibration_mismatch")

        feats = build_features(reading)
        md = self.model.metadata
        outside = [f for f, (lo, hi) in md["validated_feature_ranges"].items() if not lo <= feats[f] <= hi]
        if outside:
            return self._result(reading, report, UNCERTAIN, "operational", "outside_validated_range",
                                details={"outside_features": outside})
        X = pd.DataFrame([feats])[feature_names()]
        try:
            raw = self.model.estimator.predict_proba(X)[0]
        except Exception:  # noqa: BLE001 - never leak model internals to clients
            log.exception("Inference failed for model %s", self.model.model_id)
            return self._result(reading, report, CLASSIFICATION_UNAVAILABLE, "operational", "inference_error")
        classes = [str(c) for c in self.model.estimator.classes_]
        proba = {c: round(float(p), 4) for c, p in zip(classes, raw)}
        best = max(proba, key=proba.get)
        conf = proba[best]
        if md["abstention_threshold"] is None or conf < md["abstention_threshold"]:
            return self._result(reading, report, UNCERTAIN, "operational", "low_confidence",
                                confidence=conf, probabilities=proba)
        return self._result(reading, report, best, "thermal", "model_prediction", confidence=conf, probabilities=proba)
