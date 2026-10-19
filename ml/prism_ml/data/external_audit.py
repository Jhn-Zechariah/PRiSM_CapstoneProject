"""Feasibility audit of the external datasets, computed directly from the raw files.

Produces ``data/metadata/external_audit.json`` and ``reports/external_dataset_audit.md``. The numbers
in docs/DATASETS_AND_PROVENANCE.md are copied from these outputs.

Besides schema/quality facts, two small DESCRIPTIVE auxiliary analyses are computed. They are not used
to train or label the PRISM classifier:
* HotPig: change in video-derived drinking/lying time per pig between TN and HS conditions.
* INRAE: rise of core body temperature above each pig's own thermoneutral median, by day of the
  32 degC challenge.
"""
from __future__ import annotations

import io
import json
import zipfile
from pathlib import Path

import numpy as np
import pandas as pd

from prism_ml.config import METADATA_DIR, RAW_EXTERNAL_DIR, REPORTS_DIR

PRISM_SENSOR_KEYWORDS = ("temp", "humid", "thermal", "surface", "skin", "rh", "thi")


def _q(s: pd.Series, qs=(0.05, 0.25, 0.5, 0.75, 0.95)) -> dict:
    return {f"p{int(q * 100)}": round(float(v), 3) for q, v in s.quantile(list(qs)).items()}


def audit_hotpig(raw: Path) -> dict:
    zpath = raw / "series.zip"
    frames = []
    with zipfile.ZipFile(zpath) as z:  # read members in memory: no extraction, no path traversal
        names = sorted(n for n in z.namelist() if n.endswith(".csv"))
        for n in names:
            df = pd.read_csv(io.BytesIO(z.read(n)))
            df = df.rename(columns={df.columns[0]: "datetime"})
            df["pig"] = Path(n).stem
            frames.append(df)
    df = pd.concat(frames, ignore_index=True)
    df["datetime"] = pd.to_datetime(df["datetime"], format="%Y-%m-%d %H:%M:%S")
    step = df.sort_values(["pig", "datetime"]).groupby("pig")["datetime"].diff().dt.total_seconds().div(60)
    cols = [c for c in df.columns if c not in ("pig",)]
    sensor_like = [c for c in cols if any(k in c.lower() for k in PRISM_SENSOR_KEYWORDS)]
    per_pig = df.groupby(["pig", "conditions"])[["drinking", "lying"]].mean().div(150).unstack("conditions")
    drink_tn, drink_hs = per_pig[("drinking", "TN")], per_pig[("drinking", "HS")]
    lying_tn, lying_hs = per_pig[("lying", "TN")], per_pig[("lying", "HS")]
    return {
        "files": len(names), "rows": int(len(df)), "pigs": int(df["pig"].nunique()), "columns": cols,
        "dtypes": {c: str(t) for c, t in df[cols].dtypes.items()},
        "missing_values": {c: int(v) for c, v in df[cols].isna().sum().items() if v},
        "duplicate_pig_timestamps": int(df.duplicated(["pig", "datetime"]).sum()),
        "sampling_interval_minutes": _q(step.dropna()),
        "date_range": [str(df["datetime"].min()), str(df["datetime"].max())],
        "conditions_counts": df["conditions"].value_counts().to_dict(),
        "state_counts": df["state"].value_counts().to_dict(),
        "columns_matching_prism_sensor_keywords": sensor_like,
        "compatible_with_prism_inputs": False,
        "auxiliary_behaviour_tn_vs_hs": {
            "definition": "per-pig mean fraction of video frames per minute; TN vs HS condition",
            "drinking_fraction_mean": {"TN": round(float(drink_tn.mean()), 4), "HS": round(float(drink_hs.mean()), 4)},
            "pigs_drinking_more_in_hs": f"{int((drink_hs > drink_tn).sum())}/{len(per_pig)}",
            "lying_fraction_mean": {"TN": round(float(lying_tn.mean()), 4), "HS": round(float(lying_hs.mean()), 4)},
            "pigs_lying_more_in_hs": f"{int((lying_hs > lying_tn).sum())}/{len(per_pig)}",
        },
    }


def audit_inrae(raw: Path) -> dict:
    df = pd.read_csv(raw / "bt_raw.tab", sep="\t", encoding="utf-8", low_memory=False)
    meta = pd.read_csv(raw / "bt_metadata.tab", sep="\t", encoding="utf-8")
    raw_cols = list(df.columns)
    df["datetime"] = pd.to_datetime(df["datetime"], format="ISO8601")
    tn = df["periode"].str.startswith("Thermo")
    hs = df["periode"].str.startswith("Stress")
    key = df["id_challenge"].fillna(-1)
    step = df.assign(k=key).sort_values(["k", "porc", "datetime"]).groupby(["k", "porc"])["datetime"].diff()
    base = df[tn].assign(k=key[tn]).groupby(["k", "porc"])["T_IM"].median()
    df["k"] = key
    df["dT"] = df["T_IM"] - pd.Series(list(zip(df["k"], df["porc"]))).map(base.to_dict()).values
    hs_with_stage = df[hs & df["stage"].notna()]
    by_day = {int(d): {"n": int(len(g)), "mean": round(float(g["dT"].mean()), 3), **_q(g["dT"].dropna(), (0.5, 0.9))}
              for d, g in hs_with_stage.groupby("stage")}
    challenges_with_both = (df[tn | hs].groupby(["k", "porc"])["periode"].nunique() >= 2).sum()
    return {
        "rows": int(len(df)), "columns": raw_cols,
        "dtypes": {c: str(t) for c, t in df[raw_cols].dtypes.items()},
        "missing_values": {c: int(v) for c, v in df[raw_cols].isna().sum().items() if v},
        "pigs": int(df["porc"].nunique()), "challenges": int(df["id_challenge"].nunique()),
        "rows_without_challenge_id": int(df["id_challenge"].isna().sum()),
        "pigs_without_challenge_id": int(df.loc[df["id_challenge"].isna(), "porc"].nunique()),
        "experiments_in_metadata": int(meta["exp"].nunique()), "pigs_in_metadata": int(meta["porc"].nunique()),
        "date_only_timestamps": int((df["datetime"].dt.strftime("%H:%M:%S") == "00:00:00").sum()),
        "duplicate_pig_timestamps": int(df.duplicated(["porc", "datetime"]).sum()),
        "date_range": [str(df["datetime"].min()), str(df["datetime"].max())],
        "sampling_interval_minutes": _q(step.dt.total_seconds().div(60).dropna()),
        "periode_counts": df["periode"].value_counts().to_dict(),
        "ambient_T_distinct_values": sorted(float(v) for v in df["T"].dropna().unique()),
        "ambient_T_counts_by_periode": {p: {str(k): int(v) for k, v in g.value_counts().items()}
                                        for p, g in df.groupby("periode")["T"]},
        "core_T_IM_by_periode": {p: {"n": int(len(g)), "mean": round(float(g.mean()), 3), **_q(g)}
                                 for p, g in df.groupby("periode")["T_IM"]},
        "corr_ambient_T_vs_core_T": round(float(df[["T", "T_IM"]].corr().iloc[0, 1]), 3),
        "has_humidity": False, "has_surface_or_thermal_array_temperature": False,
        "compatible_with_prism_inputs": False,
        "auxiliary_core_temperature_rise": {
            "definition": "T_IM minus the pig's own median T_IM during the thermoneutral period, for heat-stress "
                          "rows, by experiment day (stage 0 = first day at 32 degC)",
            "pig_challenges_with_tn_and_hs": int(challenges_with_both),
            "by_stage_day": by_day,
            "all_hs_rows": {"n": int(df.loc[hs, "dT"].notna().sum()), "mean": round(float(df.loc[hs, "dT"].mean()), 3),
                            **_q(df.loc[hs, "dT"].dropna(), (0.5, 0.9, 0.99))},
            "all_tn_rows": {"mean": round(float(df.loc[tn, "dT"].mean()), 3), **_q(df.loc[tn, "dT"].dropna(), (0.5, 0.9, 0.99))},
        },
    }


def _md(audit: dict) -> str:
    h, i = audit["hotpig"], audit["inrae_core_bt"]
    a, b = h["auxiliary_behaviour_tn_vs_hs"], i["auxiliary_core_temperature_rise"]
    lines = [
        "# External dataset audit (generated by scripts/audit_external.py)", "",
        "## HotPig (doi:10.5281/zenodo.17090997)",
        f"- {h['files']} pig files, {h['rows']:,} rows, {h['pigs']} pigs, {h['date_range'][0]} to {h['date_range'][1]}",
        f"- Columns: {', '.join(h['columns'])}",
        f"- Conditions: {h['conditions_counts']}",
        f"- Columns matching temperature/humidity/thermal keywords: {h['columns_matching_prism_sensor_keywords'] or 'none'}",
        f"- Missing values: {h['missing_values'] or 'none'}; duplicate pig-timestamps: {h['duplicate_pig_timestamps']}",
        f"- Auxiliary: drinking fraction TN {a['drinking_fraction_mean']['TN']} vs HS {a['drinking_fraction_mean']['HS']} "
        f"({a['pigs_drinking_more_in_hs']} pigs higher in HS); lying fraction TN {a['lying_fraction_mean']['TN']} vs HS "
        f"{a['lying_fraction_mean']['HS']} ({a['pigs_lying_more_in_hs']} pigs higher in HS)",
        "- **Compatible with PRISM inputs: no**", "",
        "## INRAE core body temperature (doi:10.57745/GPW3E1)",
        f"- {i['rows']:,} rows, {i['pigs']} pigs, {i['challenges']} challenge ids, {i['experiments_in_metadata']} experiments; "
        f"{i['date_range'][0]} to {i['date_range'][1]}",
        f"- Columns: {', '.join(i['columns'])}",
        f"- Missing values: {i['missing_values']}",
        f"- Rows without challenge id: {i['rows_without_challenge_id']:,} ({i['pigs_without_challenge_id']} pigs); "
        f"date-only timestamps: {i['date_only_timestamps']}; duplicate pig-timestamps: {i['duplicate_pig_timestamps']}",
        f"- Ambient T distinct values: {i['ambient_T_distinct_values']} (setpoints, not continuous readings)",
        f"- Ambient T by period: {i['ambient_T_counts_by_periode']}",
        f"- Core T_IM by period: {json.dumps(i['core_T_IM_by_periode'])}",
        f"- Auxiliary core-temperature rise during heat stress (vs own TN median): all HS rows {json.dumps(b['all_hs_rows'])}; "
        f"by day {json.dumps(b['by_stage_day'])}",
        "- **Compatible with PRISM inputs: no** (core temperature, setpoint-only ambient, no humidity, no thermal array)",
    ]
    return "\n".join(lines) + "\n"


def run(raw_dir: Path = RAW_EXTERNAL_DIR, metadata_dir: Path = METADATA_DIR, reports_dir: Path = REPORTS_DIR) -> dict:
    audit = {"hotpig": audit_hotpig(raw_dir / "hotpig"), "inrae_core_bt": audit_inrae(raw_dir / "inrae_core_bt")}
    metadata_dir.mkdir(parents=True, exist_ok=True)
    reports_dir.mkdir(parents=True, exist_ok=True)
    (metadata_dir / "external_audit.json").write_text(json.dumps(audit, indent=2, default=str), encoding="utf-8")
    (reports_dir / "external_dataset_audit.md").write_text(_md(audit), encoding="utf-8")
    return audit
