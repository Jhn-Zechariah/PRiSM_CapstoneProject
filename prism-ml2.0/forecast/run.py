"""One command reproduces the B2 experiment.

  # REAL data: a Phase-1 export folder (python -m pipeline.export ...)
  python -m forecast.run --dataset exports/<dataset_version>

  # PIPELINE TEST ONLY (synthetic fixtures; every output labelled NOT VALID RESULTS)
  python -m forecast.run --pipeline-test

Report: reports/forecast/<dataset_version>/report.json and report.md
Exit codes: 0 completed, 2 stopped (not enough data), 3 no dataset.
"""
import argparse
import copy
import json
import platform
import sys
import tempfile
from pathlib import Path

import numpy as np
import pandas as pd
import sklearn

from assess import config as acfg_mod
from forecast import evaluate as ev
from forecast.data import is_synthetic, load_export, required_days, sufficiency, to_grid
from forecast.features import build_frame
from forecast.report import INVALID, VALID, apply_acceptance, conclusions, write
from pipeline.config import config_fingerprint

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "config" / "forecast.json"


def load_config(path=None):
    return json.loads(Path(path or CONFIG).read_text(encoding="utf-8"))


def alert_threshold(fcfg, acfg):
    a = fcfg["alert"]
    if fcfg["target"] != a["applies_to_target"]:
        return None, f"alert metrics apply only to target {a['applies_to_target']}"
    t = acfg["assessment"]["thi"]
    thr = (t["categories"].get(a["category"]) or {}).get("thresholds")
    if not thr:
        return None, (f"THI thresholds for category {a['category']!r} are not set in config/assessment.json, "
                      "so alert metrics cannot be computed")
    i = t["band_keys"].index(a["band_key"])
    if i == 0:
        return None, "alert band_key must be above the lowest band"
    return thr[i - 1], None


def _horizon(frame, feats, grid, fcfg, h, thr, thr_reason):
    split = ev.make_splits(frame, fcfg, h)
    if split["problems"]:
        return {"status": "not_evaluated", "reason": "; ".join(split["problems"])}
    table, best = ev.tune(frame, split, feats, fcfg)
    bl, cands = fcfg["models"]["baselines"], fcfg["models"]["candidates"]
    best_baseline = min(bl, key=lambda n: best[n]["mean_val_mae"])
    best_candidate = min(cands, key=lambda n: best[n]["mean_val_mae"])
    dev, test = frame[split["dev"]], frame[split["test"]]
    # ---- the one and only test evaluation ----
    preds = {n: ev.fit_predict(n, best[n]["params"], dev, test, feats, fcfg) for n in bl + cands}
    code, n_days = ev.day_index(test)
    R = ev.resample_matrix(n_days, fcfg)
    y = test["y_level"].to_numpy()
    out = {
        "status": "completed", "n_dev": int(len(dev)), "n_test": int(len(test)), "test_days": n_days,
        "dev_days": int(dev["local_date"].nunique()),
        "gap_minutes": int(split["gap"] / pd.Timedelta(minutes=1)),
        "test_start": split["test_start"].isoformat(), "dev_end": split["dev_end"].isoformat(),
        "folds": [{k: (v.isoformat() if hasattr(v, "isoformat") else v) for k, v in f.items()
                   if k not in ("train", "val")} for f in split["folds"]],
        "tuning": table, "chosen_params": {n: best[n]["params"] for n in best},
        "val_mae": {n: best[n]["mean_val_mae"] for n in best},
        "baselines": bl, "candidates": cands,
        "best_baseline": best_baseline, "best_candidate": best_candidate,
        "test": ev.error_stats(y, preds, best_baseline, code, n_days, R, fcfg),
        "hottest_hours": ev.hottest_hours_mae(dev, test, preds, fcfg),
        "error_analysis": ev.error_analysis(dev, test, preds, fcfg),
        "held_out_pen": ev.held_out_pen(frame, split, feats, best, fcfg),
    }
    out["alerts"] = (ev.alert_metrics(test, preds, thr, grid, h, code, n_days, R, fcfg)
                     if thr is not None else {"reason": thr_reason})
    return out


def run_experiment(dataset_dir, fcfg, acfg, out_root):
    df, manifest = load_export(dataset_dir)
    synthetic = is_synthetic(df, manifest)
    version = manifest.get("dataset_version", Path(dataset_dir).name)
    rep = {
        "validity": INVALID if synthetic else VALID,
        "status": "running", "dataset_version": version, "dataset_dir": str(dataset_dir),
        "dataset_manifest": {k: manifest.get(k) for k in ("record_count", "quality_counts", "schema_version",
                                                          "effective_time_range_utc", "config_sha256")},
        "config_version": f"forecast-{fcfg['version']}", "config_status": fcfg.get("status"),
        "config_sha256": config_fingerprint(fcfg, acfg["assessment"]),
        "assessment_config_version": acfg["version"],
        "seed": fcfg["seed"], "bootstrap": fcfg["bootstrap"], "target": fcfg["target"],
        "predict": fcfg["predict"], "horizons_minutes": fcfg["horizons_minutes"],
        "software": {"python": platform.python_version(), "scikit-learn": sklearn.__version__,
                     "numpy": np.__version__, "pandas": pd.__version__},
    }
    grid, summary = to_grid(df, fcfg, acfg)
    rep["data_summary"] = summary
    rep["sufficiency"] = suff = sufficiency(grid, fcfg)
    out_dir = Path(out_root) / version

    if not suff["sufficient"]:
        need = required_days(fcfg)
        rep["status"] = "stopped_insufficient_data" + ("_pipeline_test" if synthetic else "_real_data")
        needed = [f"at least {need} independent local days with >= {suff['min_day_coverage_pct']}% usable "
                  f"{fcfg['target']} bins (have {suff['independent_days']})"]
        if summary.get("usable_dht_temp_c_records", 0) == 0:
            needed.append("DHT22 air temperature in the history records: current firmware stores `ambientTemp` "
                          "only in live_sensor/latest, not in sensor_readings_seconds (see "
                          "docs/FIRMWARE_PROPOSAL_sensor_v2.md); THI and pen temperature need it")
        if not summary.get("misting_logged"):
            needed.append("misting state in history records (`sprinkler`, `sprinklerActiveSec`) for misting "
                          "features and error analysis (optional)")
        rep["stop"] = {"message": "Not enough usable data to evaluate honestly. No model was trained or scored.",
                       "needed": needed}
        rep["acceptance"] = apply_acceptance(fcfg.get("acceptance_rule"), {}, synthetic)
        return rep, write(rep, out_dir), 2

    thr, thr_reason = alert_threshold(fcfg, acfg)
    rep["alert_threshold"] = thr
    horizons, feats = {}, []
    for h in fcfg["horizons_minutes"]:
        frame, feats = build_frame(grid, fcfg, h)
        horizons[str(h)] = _horizon(frame, feats, grid, fcfg, h, thr, thr_reason)
    rep["features"] = feats
    rep["horizons"] = horizons
    rep["conclusions"], rep["any_candidate_beat_best_baseline"] = conclusions(horizons)
    if synthetic:
        rep["conclusions"] = [f"[{INVALID}] " + c for c in rep["conclusions"]]
    rep["acceptance"] = apply_acceptance(fcfg.get("acceptance_rule"), horizons, synthetic)
    rep["status"] = "completed"
    return rep, write(rep, out_dir), 0


def pipeline_test_configs(acfg, fcfg):
    """SYNTHETIC alert threshold so the alert code path is exercised. Test-only values."""
    a = copy.deepcopy(acfg["assessment"])
    a["_synthetic_test_config"] = True
    a["thi"]["categories"][fcfg["alert"]["category"]] = {"thresholds": [80.0, 84.0], "hysteresis": 1.0}
    return acfg_mod.build(a, acfg["labels"])


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    src = p.add_mutually_exclusive_group(required=True)
    src.add_argument("--dataset", help="Phase-1 export folder (contains manifest.json)")
    src.add_argument("--pipeline-test", action="store_true", help="run on SYNTHETIC fixtures (not valid results)")
    p.add_argument("--config", help="forecast config (default config/forecast.json)")
    p.add_argument("--out", default=str(ROOT / "reports" / "forecast"))
    p.add_argument("--days", type=int, default=40, help="pipeline test: synthetic days")
    a = p.parse_args(argv)

    fcfg = load_config(a.config)
    acfg = acfg_mod.load()
    if a.pipeline_test:
        from pipeline.export import export
        from tests.fixtures.synthetic_forecast import generate
        acfg = pipeline_test_configs(acfg, fcfg)
        with tempfile.TemporaryDirectory() as tmp:
            target, _ = export(generate(days=a.days), tmp, input_desc="SYNTHETIC forecast pipeline test")
            rep, out, code = run_experiment(target, fcfg, acfg, a.out)
    else:
        if not Path(a.dataset).is_dir():
            print(f"No dataset at {a.dataset}. Export real data first:\n"
                  "  pip install -r requirements-data.txt\n"
                  "  python -m pipeline.export --firestore --start YYYY-MM-DD --end YYYY-MM-DD --out exports",
                  file=sys.stderr)
            return 3
        rep, out, code = run_experiment(a.dataset, fcfg, acfg, a.out)
    print(f"[{rep['validity']}] status={rep['status']} report={out / 'report.md'}")
    for line in rep.get("conclusions", []):
        print(" -", line)
    if rep.get("stop"):
        print(" STOPPED:", rep["stop"]["message"])
        for n in rep["stop"]["needed"]:
            print("   needed:", n)
    print(" acceptance:", rep["acceptance"]["reason"])
    return code


if __name__ == "__main__":
    sys.exit(main())
