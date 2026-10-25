"""Load a Phase-1 export, keep usable readings, resample to a regular grid, check sufficiency."""
import json
import math
from pathlib import Path

import numpy as np
import pandas as pd

from assess.thi_band import compute_thi

TARGET_COLUMN = {"thi": "thi", "dht_temp_c": "temp"}


def load_export(path):
    p = Path(path)
    if not (p / "manifest.json").is_file():
        raise FileNotFoundError(f"{p} is not an export folder (no manifest.json). "
                                "Create one with: python -m pipeline.export --firestore ...")
    manifest = json.loads((p / "manifest.json").read_text(encoding="utf-8"))
    if (p / "readings.parquet").is_file():
        df = pd.read_parquet(p / "readings.parquet")
    else:
        df = pd.read_csv(p / "readings.csv", low_memory=False)
    return df, manifest


def is_synthetic(df, manifest):
    return bool(manifest.get("contains_synthetic")
                or str(manifest.get("dataset_version", "")).startswith("SYNTHETIC-")
                or ("synthetic" in df.columns and df["synthetic"].astype(str).str.lower().eq("true").any()))


def _as_float_bool(s):
    if s is None:
        return None
    m = {"true": 1.0, "false": 0.0, "1": 1.0, "0": 0.0, "1.0": 1.0, "0.0": 0.0}
    return s.map(lambda v: m.get(str(v).strip().lower(), np.nan) if pd.notna(v) else np.nan)


def to_grid(df, fcfg, acfg):
    """Returns (grid, summary). grid: one row per pen per resample bin with
    temp, hum, thi, n_records, n_fault, mist_on, mist_active_s (NaN where no usable data)."""
    u, step = fcfg["usable_records"], fcfg["resample_minutes"]
    summary = {"raw_records": int(len(df))}
    t = pd.to_datetime(df.get("effective_time_utc"), utc=True, errors="coerce", format="ISO8601")
    keep = t.notna()
    if u.get("require_time_basis"):
        keep &= df.get("time_basis").astype(str) == u["require_time_basis"]
    if u.get("exclude_duplicates") and "duplicate_of" in df:
        keep &= df["duplicate_of"].fillna("").astype(str) == ""
    d = df[keep].copy()
    d["time"] = t[keep]
    summary["records_with_trusted_time_not_duplicate"] = int(len(d))
    if "schema_version" in df:
        summary["schema_versions"] = {str(k): int(v) for k, v in df["schema_version"].value_counts().items()}

    pen = d["pen_id"] if "pen_id" in d else pd.Series(np.nan, index=d.index)
    d["pen"] = pen.where(pen.notna() & (pen.astype(str) != ""), d.get("device_key", "unknown")).astype(str)

    fault = pd.Series(False, index=d.index)
    for col, out in (("dht_temp_c", "temp"), ("dht_humidity_pct", "hum")):
        state = d.get(f"{col}__state", pd.Series("missing", index=d.index)).astype(str)
        val = pd.to_numeric(d.get(col), errors="coerce") if col in d else pd.Series(np.nan, index=d.index)
        d[out] = val.where(state == u["usable_channel_state"])
        fault |= state.isin(u["fault_channel_states"])
        summary[f"usable_{col}_records"] = int(d[out].notna().sum())
    d["fault"] = fault.astype(int)
    d["mist_on"] = _as_float_bool(d.get("sprinkler_on")) if "sprinkler_on" in d else np.nan
    d["mist_active_s"] = pd.to_numeric(d.get("sprinkler_active_s"), errors="coerce") if "sprinkler_active_s" in d else np.nan

    if d.empty:
        summary["pens"] = []
        return pd.DataFrame(columns=["pen", "time", "temp", "hum", "thi", "n_records", "n_fault",
                                     "mist_on", "mist_active_s"]), summary

    d["bin"] = d["time"].dt.floor(f"{step}min")
    g = d.groupby(["pen", "bin"]).agg(temp=("temp", "mean"), hum=("hum", "mean"),
                                      n_records=("time", "size"), n_fault=("fault", "sum"),
                                      mist_on=("mist_on", "max"), mist_active_s=("mist_active_s", "max"))
    frames = []
    for pen_id, gp in g.groupby(level="pen"):
        gp = gp.droplevel("pen")
        full = pd.date_range(gp.index.min(), gp.index.max(), freq=f"{step}min")
        gp = gp.reindex(full)
        gp["n_records"] = gp["n_records"].fillna(0).astype(int)
        gp["n_fault"] = gp["n_fault"].fillna(0).astype(int)
        gp = gp.rename_axis("time").reset_index()
        gp.insert(0, "pen", pen_id)
        frames.append(gp)
    grid = pd.concat(frames, ignore_index=True)
    grid["thi"] = [compute_thi(a, b, acfg) if pd.notna(a) and pd.notna(b) else np.nan
                   for a, b in zip(grid["temp"], grid["hum"])]
    summary["pens"] = sorted(grid["pen"].unique().tolist())
    summary["misting_logged"] = bool(grid["mist_on"].notna().any())
    return grid, summary


def required_days(fcfg):
    s = fcfg["splits"]
    gap_days = math.ceil(max(max(fcfg["horizons_minutes"]), s["min_gap_minutes"]) / 1440)
    return s["min_train_days"] + s["n_folds"] * s["val_days"] + s["test_days"] + gap_days


def sufficiency(grid, fcfg):
    """Counts independent (local calendar) days with enough usable target bins."""
    target = TARGET_COLUMN[fcfg["target"]]
    need = required_days(fcfg)
    per_day_bins = 1440 // fcfg["resample_minutes"]
    out = {"target": fcfg["target"], "required_independent_days": need,
           "min_day_coverage_pct": fcfg["sufficiency"]["min_day_coverage_pct"],
           "usable_target_bins": int(grid[target].notna().sum()) if len(grid) else 0}
    if not len(grid) or not grid[target].notna().any():
        out.update(independent_days=0, days=[], sufficient=False)
        return out
    local = grid["time"].dt.tz_convert(fcfg["timezone"])
    cov = (grid.assign(date=local.dt.date, ok=grid[target].notna())
           .groupby(["pen", "date"])["ok"].sum() / per_day_bins * 100)
    ok_days = sorted({str(dt) for (_, dt), c in cov.items() if c >= out["min_day_coverage_pct"]})
    out.update(independent_days=len(ok_days), first_day=ok_days[0] if ok_days else None,
               last_day=ok_days[-1] if ok_days else None, sufficient=len(ok_days) >= need)
    return out
