"""Loading genuine local PRISM observations and reviewer-assigned labels into a training table.

Raw inputs (kept unchanged under ``data/raw/local/``):

* ``readings/*.csv`` – one row per sensor reading (see ``READING_COLUMNS``), e.g. produced by
  ``scripts/export_readings.py``.
* ``labels/*.csv`` – one row per *label session*: a qualified reviewer's assessment of one pen during a
  short time window (see ``LABEL_COLUMNS`` and docs/FARM_DATA_COLLECTION_AND_RETRAINING.md).

A reading receives a label only if it falls inside exactly one TRUSTED label session for the same farm
and pen. Readings never receive labels from sensor values or thresholds.
"""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import pandas as pd

from prism_ml.config import RAW_LOCAL_DIR, load_config
from prism_ml.data.quality import check_reading
from prism_ml.features.contract import build_features, feature_names
from prism_ml.reading import THERMAL_STATUSES, SensorReading

READING_COLUMNS = [
    "reading_id", "device_id", "farm_id", "pen_id", "observed_at",
    "air_temp_c", "air_temp_valid", "relative_humidity_pct", "humidity_valid",
    "thermal_pixels_c", "thermal_valid", "water_level_pct", "water_valid",
    "calibration_profile", "data_origin",
]
LABEL_COLUMNS = [
    "label_session_id", "farm_id", "pen_id", "window_start", "window_end", "status",
    "label_confidence", "reviewer_id", "reviewer_role", "reviewer_blinded", "assessment_method",
    "respiration_rate_bpm", "panting", "lying_apart", "pen_fouling", "rectal_temp_c",
    "protocol_version", "labeled_at", "notes",
]
TRUSTED_CONFIDENCE = {"confirmed"}
TRUSTED_ROLES = {"veterinarian", "agricultural_expert", "trained_observer"}
SUPPORTED_PROTOCOLS = {"PRISM-LABEL-1.0"}
MAX_WINDOW_MINUTES = 30
GENUINE_ORIGIN = "farm"
FIXTURE_ORIGIN = "synthetic_test_fixture"


class DatasetError(ValueError):
    pass


@dataclass
class LocalDataset:
    frame: pd.DataFrame                       # features + target + grouping columns
    summary: dict = field(default_factory=dict)

    @property
    def X(self) -> pd.DataFrame:
        return self.frame[feature_names()]

    @property
    def y(self) -> pd.Series:
        return self.frame["status"]


def _bool(v) -> Optional[bool]:
    if isinstance(v, bool):
        return v
    if v is None or (isinstance(v, float) and pd.isna(v)):
        return None
    s = str(v).strip().lower()
    if s in ("true", "1", "yes", "y"):
        return True
    if s in ("false", "0", "no", "n"):
        return False
    return None


def _num(v) -> Optional[float]:
    try:
        f = float(v)
    except (TypeError, ValueError):
        return None
    return None if pd.isna(f) else f


def _sha256_files(paths: list[Path]) -> dict[str, str]:
    out = {}
    for p in paths:
        out[p.name] = hashlib.sha256(p.read_bytes()).hexdigest()
    return out


def _read_csvs(directory: Path, required: list[str]) -> tuple[pd.DataFrame, list[Path]]:
    files = sorted(directory.glob("*.csv"))
    if not files:
        return pd.DataFrame(columns=required), []
    frames = []
    for f in files:
        df = pd.read_csv(f, dtype=str, keep_default_na=False, na_values=[""])
        missing = [c for c in required if c not in df.columns]
        if missing:
            raise DatasetError(f"{f.name} is missing columns: {missing}")
        df["_source_file"] = f.name
        frames.append(df)
    return pd.concat(frames, ignore_index=True), files


def split_trusted_labels(labels: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Return (trusted, untrusted). Untrusted labels are kept for review, never for training."""
    labels = labels.copy()
    labels["window_start"] = pd.to_datetime(labels["window_start"], utc=True, errors="coerce")
    labels["window_end"] = pd.to_datetime(labels["window_end"], utc=True, errors="coerce")
    minutes = (labels["window_end"] - labels["window_start"]).dt.total_seconds() / 60
    reasons = pd.Series([""] * len(labels), index=labels.index, dtype=object)

    def flag(mask, reason):
        reasons[mask & (reasons == "")] = reason

    flag(~labels["status"].isin(THERMAL_STATUSES), "unknown_status")
    flag(~labels["label_confidence"].str.lower().isin(TRUSTED_CONFIDENCE), "not_confirmed")
    flag(~labels["reviewer_role"].str.lower().isin(TRUSTED_ROLES), "reviewer_role_not_accepted")
    blinded = labels["reviewer_blinded"].map(lambda v: _bool(v) is True)
    flag(~blinded.astype(bool), "reviewer_not_blinded")
    flag(~labels["protocol_version"].isin(SUPPORTED_PROTOCOLS), "unsupported_protocol")
    flag(labels["window_start"].isna() | labels["window_end"].isna(), "bad_window")
    flag((minutes <= 0) | (minutes > MAX_WINDOW_MINUTES), "window_length_invalid")
    flag(labels["label_session_id"].duplicated(keep=False), "duplicate_session_id")
    labels["untrusted_reason"] = reasons
    return labels[reasons == ""].drop(columns="untrusted_reason"), labels[reasons != ""]


def load_local_dataset(root: Optional[Path] = None, allow_fixtures: bool = False) -> LocalDataset:
    root = Path(root) if root else RAW_LOCAL_DIR
    readings, reading_files = _read_csvs(root / "readings", READING_COLUMNS)
    labels, label_files = _read_csvs(root / "labels", LABEL_COLUMNS)

    origins = set(readings["data_origin"].dropna().unique()) if len(readings) else set()
    if FIXTURE_ORIGIN in origins and not allow_fixtures:
        raise DatasetError("Synthetic test fixtures found in the local dataset; they must never be used for training")
    unknown = origins - {GENUINE_ORIGIN, FIXTURE_ORIGIN}
    if unknown:
        raise DatasetError(f"Unknown data_origin values: {sorted(unknown)}")

    summary: dict = {
        "reading_files": _sha256_files(reading_files),
        "label_files": _sha256_files(label_files),
        "raw_readings": int(len(readings)),
        "raw_label_sessions": int(len(labels)),
        "contains_synthetic_fixtures": FIXTURE_ORIGIN in origins,
    }
    if readings.empty or labels.empty:
        summary.update(trusted_label_sessions=0, labeled_readings=0)
        return LocalDataset(pd.DataFrame(columns=feature_names() + ["status"]), summary)

    dup = readings["reading_id"].duplicated(keep="first")
    summary["duplicate_readings_dropped"] = int(dup.sum())
    readings = readings[~dup].copy()
    readings["observed_at"] = pd.to_datetime(readings["observed_at"], utc=True, errors="coerce")

    trusted, untrusted = split_trusted_labels(labels)
    summary["trusted_label_sessions"] = int(len(trusted))
    summary["untrusted_label_sessions"] = int(len(untrusted))
    summary["untrusted_reasons"] = untrusted["untrusted_reason"].value_counts().to_dict() if len(untrusted) else {}

    # --- match readings to label sessions -------------------------------------------------------
    merged = readings.merge(trusted, on=["farm_id", "pen_id"], how="inner", suffixes=("", "_label"))
    inside = (merged["observed_at"] >= merged["window_start"]) & (merged["observed_at"] <= merged["window_end"])
    merged = merged[inside]
    n_labels = merged.groupby("reading_id")["status"].nunique()
    conflicting = set(n_labels[n_labels > 1].index)
    n_sessions = merged.groupby("reading_id")["label_session_id"].nunique()
    overlapping = set(n_sessions[n_sessions > 1].index)
    summary["readings_with_conflicting_labels_dropped"] = len(conflicting)
    summary["readings_in_overlapping_sessions_dropped"] = len(overlapping - conflicting)
    merged = merged[~merged["reading_id"].isin(conflicting | overlapping)]

    # --- data-quality layer (identical rules to inference, minus freshness) ---------------------
    rows, rejected = [], {}
    for r in merged.itertuples(index=False):
        try:
            pixels = json.loads(r.thermal_pixels_c) if isinstance(r.thermal_pixels_c, str) else None
        except json.JSONDecodeError:
            pixels = None
        reading = SensorReading(
            observed_at=r.observed_at.to_pydatetime() if pd.notna(r.observed_at) else None,
            air_temp_c=_num(r.air_temp_c), air_temp_valid=_bool(r.air_temp_valid),
            relative_humidity_pct=_num(r.relative_humidity_pct), humidity_valid=_bool(r.humidity_valid),
            thermal_pixels_c=pixels, thermal_valid=_bool(r.thermal_valid),
            calibration_profile=r.calibration_profile if isinstance(r.calibration_profile, str) else None,
            device_id=r.device_id,
        )
        report = check_reading(reading, check_freshness=False)
        if not report.ok:
            for issue in report.blocking:
                rejected[issue.code] = rejected.get(issue.code, 0) + 1
            continue
        feats = build_features(reading)
        feats.update(status=r.status, label_session_id=r.label_session_id, farm_id=r.farm_id, pen_id=r.pen_id,
                     reading_id=r.reading_id, observed_at=r.observed_at, window_start=r.window_start,
                     calibration_profile=reading.calibration_profile or "", data_origin=r.data_origin)
        rows.append(feats)
    summary["readings_rejected_by_quality_layer"] = rejected
    frame = pd.DataFrame(rows)
    summary["labeled_readings"] = int(len(frame))
    if len(frame):
        summary["class_counts"] = frame["status"].value_counts().to_dict()
        summary["sessions_per_class"] = frame.groupby("status")["label_session_id"].nunique().to_dict()
        summary["farms"] = int(frame["farm_id"].nunique())
        summary["observed_range"] = [str(frame["observed_at"].min()), str(frame["observed_at"].max())]
        summary["calibration_profiles"] = sorted(frame["calibration_profile"].unique().tolist())
    return LocalDataset(frame, summary)


def requirements_report(ds: LocalDataset) -> list[str]:
    """Return unmet acceptance data requirements (empty list = enough trusted data to attempt training)."""
    req = load_config("acceptance")["data_requirements"]
    problems = []
    f = ds.frame
    if len(f) < req["min_trusted_labeled_readings"]:
        problems.append(f"{len(f)} trusted labeled readings < required {req['min_trusted_labeled_readings']}")
    sessions = f["label_session_id"].nunique() if len(f) else 0
    if sessions < req["min_label_sessions"]:
        problems.append(f"{sessions} label sessions < required {req['min_label_sessions']}")
    per_class = f.groupby("status")["label_session_id"].nunique().to_dict() if len(f) else {}
    for cls in THERMAL_STATUSES:
        if per_class.get(cls, 0) < req["min_label_sessions_per_class"]:
            problems.append(f"class '{cls}' has {per_class.get(cls, 0)} label sessions < required "
                            f"{req['min_label_sessions_per_class']}")
    return problems
