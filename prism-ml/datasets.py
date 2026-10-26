"""Load synthetic / real data as supervised tables and split them by time.

Splits are always chronological (whole days), never shuffled:
  synthetic : first 70% of days train, next 15% validation, last 15% test
  real      : a frozen block of the latest real days (models/real_holdout.json) is the
              test set and is never trained on; of the remaining days the most recent
              `real_val_fraction` are validation, the rest train
  combined  : all synthetic days go to train; real days split as above;
              real rows get `sample_weight_real`
"""
from __future__ import annotations

import json
import math

import numpy as np
import pandas as pd

from common import (HOLDOUT_PATH, REAL_PARTS_DIR, SPRINKLER_LOGS_PATH, SYNTHETIC_PATH, load_config)
from features import make_supervised
from preprocess import to_minute_frame


# ----------------------------------------------------------------------------- loading
def load_synthetic_frame(cfg: dict | None = None) -> pd.DataFrame:
    cfg = cfg or load_config()
    if not SYNTHETIC_PATH.exists():
        from simulate import simulate
        SYNTHETIC_PATH.parent.mkdir(parents=True, exist_ok=True)
        simulate(cfg).to_parquet(SYNTHETIC_PATH, index=False)
    raw = pd.read_parquet(SYNTHETIC_PATH)
    return to_minute_frame(raw.drop(columns=["source", "scenario", "bias_regime"], errors="ignore"),
                           cfg, source="synthetic")


def load_real_raw() -> tuple[pd.DataFrame | None, pd.DataFrame | None]:
    parts = sorted(REAL_PARTS_DIR.glob("*.parquet")) if REAL_PARTS_DIR.exists() else []
    if not parts:
        return None, None
    raw = pd.concat([pd.read_parquet(p) for p in parts], ignore_index=True)
    raw = raw.drop_duplicates("timestamp").sort_values("timestamp")
    logs = pd.read_parquet(SPRINKLER_LOGS_PATH) if SPRINKLER_LOGS_PATH.exists() else None
    return raw, logs


def load_real_frame(cfg: dict | None = None) -> pd.DataFrame | None:
    cfg = cfg or load_config()
    raw, logs = load_real_raw()
    if raw is None or raw.empty:
        return None
    return to_minute_frame(raw, cfg, logs=logs, source="real")


def local_day(index: pd.DatetimeIndex, cfg: dict) -> np.ndarray:
    return index.tz_convert(cfg["project"]["timezone"]).strftime("%Y-%m-%d").to_numpy()


def supervised(frame: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    sup = make_supervised(frame, cfg)
    sup["day"] = local_day(sup.index, cfg)
    return sup


# ----------------------------------------------------------------------------- splitting
def split_days_chronological(days, fractions: dict) -> dict[str, list[str]]:
    """Assign whole days, in time order, to train / val / test."""
    days = sorted(set(days))
    n = len(days)
    if n < 3:
        raise ValueError(f"Need at least 3 days to split by time, got {n}")
    n_test = max(1, round(n * fractions["test"]))
    n_val = max(1, round(n * fractions["val"]))
    n_train = n - n_val - n_test
    if n_train < 1:
        raise ValueError(f"Not enough days ({n}) for train/val/test")
    return {"train": days[:n_train], "val": days[n_train:n_train + n_val], "test": days[n_train + n_val:]}


def real_holdout_days(real_days, cfg: dict, create: bool = True) -> list[str]:
    """The frozen block of real test days. Created once (latest N days), then reused."""
    if HOLDOUT_PATH.exists():
        return json.loads(HOLDOUT_PATH.read_text())["days"]
    days = sorted(set(real_days))
    n = cfg["training"]["real_holdout_days"]
    if len(days) <= n + 1:
        raise ValueError(f"Need more than {n + 1} real days before freezing a hold-out block, got {len(days)}")
    held = days[-n:]
    if create:
        HOLDOUT_PATH.parent.mkdir(parents=True, exist_ok=True)
        HOLDOUT_PATH.write_text(json.dumps({
            "days": held,
            "note": "Frozen real test block. Never used for training. Delete only on purpose."}, indent=2))
    return held


def split_real_days(real_days, cfg: dict) -> dict[str, list[str]]:
    held = set(real_holdout_days(real_days, cfg))
    rest = sorted(d for d in set(real_days) if d not in held)
    if len(rest) < 2:
        raise ValueError(f"Need at least 2 non-held-out real days, got {len(rest)}")
    n_val = max(1, math.ceil(len(rest) * cfg["training"]["real_val_fraction"]))
    return {"train": rest[:-n_val], "val": rest[-n_val:], "test": sorted(held)}


def build_splits(data: str, cfg: dict | None = None) -> dict:
    """Return {"train","val","test": DataFrame, "weights": {...}, "days": {...}} for a data source."""
    cfg = cfg or load_config()
    out = {"days": {}}
    if data in ("synthetic", "combined"):
        syn = supervised(load_synthetic_frame(cfg), cfg)
    if data in ("real", "combined"):
        real_frame = load_real_frame(cfg)
        if real_frame is None:
            raise FileNotFoundError("No real data found. Run export_firestore.py first.")
        real = supervised(real_frame, cfg)
        rd = split_real_days(real["day"], cfg)
        out["days"]["real"] = rd

    if data == "synthetic":
        sd = split_days_chronological(syn["day"], cfg["training"]["split_fractions"])
        out["days"]["synthetic"] = sd
        parts = {k: syn[syn["day"].isin(v)] for k, v in sd.items()}
    elif data == "real":
        parts = {k: real[real["day"].isin(v)] for k, v in rd.items()}
    elif data == "combined":
        out["days"]["synthetic"] = {"train": sorted(set(syn["day"]))}
        parts = {
            "train": pd.concat([syn, real[real["day"].isin(rd["train"])]]).sort_index(kind="stable"),
            "val": real[real["day"].isin(rd["val"])],
            "test": real[real["day"].isin(rd["test"])],
        }
    else:
        raise ValueError(f"unknown data source {data!r}")

    w_real = cfg["training"]["sample_weight_real"] if data == "combined" else 1.0
    for k, df in parts.items():
        out[k] = df
        out.setdefault("weights", {})[k] = np.where(df["source"] == "real", w_real, 1.0)
    return out
