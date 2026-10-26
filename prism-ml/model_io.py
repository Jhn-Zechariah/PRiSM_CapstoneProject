"""Saving, loading and running a trained forecaster bundle.

A bundle is a plain dict saved with joblib (no custom classes, so it loads
anywhere the pinned library versions are installed):
  estimators: {horizon_min: fitted regressor, or None for persistence}
  target: "delta"  -> each regressor predicts pigBodyTemp(t+h) - pigBodyTemp(t)
"""
from __future__ import annotations

import shutil
from datetime import datetime, timezone
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

from common import ARCHIVE_DIR, CURRENT_MODEL_PATH, PIG


def predict(bundle: dict, X: pd.DataFrame) -> dict[int, np.ndarray]:
    """Absolute pigBodyTemp forecasts per horizon for feature rows X."""
    Xf = X[bundle["feature_columns"]]
    current = Xf[PIG].to_numpy(dtype=float)
    out = {}
    for h, est in bundle["estimators"].items():
        delta = np.zeros(len(Xf)) if est is None else np.asarray(est.predict(Xf), dtype=float)
        out[int(h)] = current + delta
    return out


def save(bundle: dict, path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(bundle, path, compress=3)
    return path


def load(path: Path | str = CURRENT_MODEL_PATH) -> dict:
    return joblib.load(path)


def archive_current() -> Path | None:
    """Copy the deployed model to models/archive/ with a timestamp (for rollback)."""
    if not CURRENT_MODEL_PATH.exists():
        return None
    ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)
    try:
        version = load(CURRENT_MODEL_PATH).get("version", "unknown")
    except Exception:
        version = "unreadable"
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    dest = ARCHIVE_DIR / f"model_{stamp}_{version}.joblib"
    shutil.copy2(CURRENT_MODEL_PATH, dest)
    return dest


def promote(candidate: Path) -> Path | None:
    """Archive the current model, then install `candidate` as current. Returns the archive path."""
    archived = archive_current()
    CURRENT_MODEL_PATH.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(candidate, CURRENT_MODEL_PATH)
    return archived
