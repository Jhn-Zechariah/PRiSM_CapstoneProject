"""SYNTHETIC TEST FIXTURES - FOR SOFTWARE TESTING ONLY.

Everything generated here is artificial. It exists solely to exercise the code paths of the data
loader, training pipeline, registry and API. It is NOT research data, it says nothing about real pigs,
and any metric computed on it is meaningless. Every row is tagged ``data_origin=synthetic_test_fixture``;
``load_local_dataset`` refuses such rows unless a test passes ``allow_fixtures=True``, and the model
registry refuses to approve or serve a model trained on them.
"""
from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

import numpy as np
import pandas as pd

from prism_ml.data.local_dataset import FIXTURE_ORIGIN, LABEL_COLUMNS, READING_COLUMNS
from prism_ml.reading import SensorReading

CLASSES = ["Good", "Needs Attention", "High Risk"]
FIXTURE_CAL = "fixture-cal-1"


def frame(hot: float, background: float, rng=None, n_hot: int = 6) -> list[float]:
    rng = rng or np.random.default_rng(0)
    px = background + rng.normal(0, 0.3, 64)
    px[:n_hot] = hot + rng.normal(0, 0.2, n_hot)
    return [round(float(p), 2) for p in px]


def reading(age_s: float = 5, now: datetime | None = None, **kw) -> SensorReading:
    now = now or datetime.now(timezone.utc)
    base = dict(observed_at=now - timedelta(seconds=age_s), air_temp_c=29.0, air_temp_valid=True,
                relative_humidity_pct=75.0, humidity_valid=True, thermal_pixels_c=frame(35.0, 29.0),
                thermal_valid=True, water_level_pct=80.0, water_valid=True, calibration_profile=FIXTURE_CAL)
    base.update(kw)
    return SensorReading(**base)


def write_fixture_dataset(root: Path, n_sessions: int = 36, per_session: int = 25, separable: bool = True,
                          seed: int = 7) -> Path:
    rng = np.random.default_rng(seed)
    (root / "readings").mkdir(parents=True, exist_ok=True)
    (root / "labels").mkdir(parents=True, exist_ok=True)
    start = datetime(2026, 3, 1, 9, tzinfo=timezone.utc)
    readings, labels = [], []
    for s in range(n_sessions):
        cls = CLASSES[s % 3]
        t0 = start + timedelta(days=s // 3, hours=(s % 3) * 2)
        air_c = {"Good": 26.0, "Needs Attention": 30.5, "High Risk": 34.5}[cls]
        hot_c = {"Good": 34.0, "Needs Attention": 36.0, "High Risk": 38.0}[cls]
        label = cls if separable else CLASSES[int(rng.integers(3))]
        labels.append({
            "label_session_id": f"S{s:03d}", "farm_id": "fixture-farm", "pen_id": "pen-1",
            "window_start": t0.isoformat(), "window_end": (t0 + timedelta(seconds=10 * per_session)).isoformat(),
            "status": label, "label_confidence": "confirmed", "reviewer_id": "fixture-reviewer",
            "reviewer_role": "veterinarian", "reviewer_blinded": "true", "assessment_method": "fixture",
            "respiration_rate_bpm": "", "panting": "", "lying_apart": "", "pen_fouling": "", "rectal_temp_c": "",
            "protocol_version": "PRISM-LABEL-1.0", "labeled_at": t0.isoformat(), "notes": "SYNTHETIC TEST FIXTURE",
        })
        for i in range(per_session):
            air = air_c + rng.normal(0, 0.8)
            readings.append({
                "reading_id": f"R{s:03d}-{i:03d}", "device_id": "fixture-device", "farm_id": "fixture-farm",
                "pen_id": "pen-1", "observed_at": (t0 + timedelta(seconds=10 * i)).isoformat(),
                "air_temp_c": round(air, 2), "air_temp_valid": "true",
                "relative_humidity_pct": round(float(rng.uniform(60, 90)), 1), "humidity_valid": "true",
                "thermal_pixels_c": json.dumps(frame(hot_c + rng.normal(0, 0.6), air - 1.0, rng)),
                "thermal_valid": "true", "water_level_pct": "80", "water_valid": "true",
                "calibration_profile": FIXTURE_CAL, "data_origin": FIXTURE_ORIGIN,
            })
    pd.DataFrame(readings, columns=READING_COLUMNS).to_csv(root / "readings" / "fixture_readings.csv", index=False)
    pd.DataFrame(labels, columns=LABEL_COLUMNS).to_csv(root / "labels" / "fixture_labels.csv", index=False)
    return root
