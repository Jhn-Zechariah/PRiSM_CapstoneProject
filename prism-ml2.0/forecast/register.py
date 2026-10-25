"""Package the experiment's best candidate into the model registry (does NOT activate it).

  python -m forecast.register --report reports/forecast/<v>/report.json \
                              --dataset exports/<v> --horizon 60

The model is refit on all rows with the hyperparameters chosen on validation folds.
Every model is registered as "candidate". forecast/retrain.py then runs the evaluation
gate (eligible or rejected); an admin approves; activation is a separate admin action.
Only "approved" models can be served.
Activation is a separate admin action: POST /models/<version>/activate.
"""
import argparse
import json
import os
import platform
import shutil
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
import sklearn

from assess import config as acfg_mod
from forecast.data import is_synthetic, load_export, to_grid
from forecast.evaluate import make_model
from forecast.features import build_frame
from forecast.report import VALID
from forecast.run import load_config
from pipeline.config import config_fingerprint

ROOT = Path(__file__).resolve().parent.parent


def report_gate(report, horizon, candidate, synthetic):
    """First half of the evaluation gate (vs the baselines). Returns (passed, reason).
    The second half, vs the production model, is in forecast/retrain.py."""
    a = report.get("acceptance") or {}
    if synthetic or report.get("validity") != VALID:
        return False, "trained on synthetic data / not a valid real-data report"
    if not a.get("allowed"):
        return False, f"acceptance rule did not pass against the baselines: {a.get('reason')}"
    if a.get("horizon_minutes") != horizon or a.get("candidate") != candidate:
        return False, "acceptance was granted for a different horizon or candidate"
    return True, "acceptance rule passed against the baselines on real data"


def register(report_path, dataset_dir, horizon, registry_root, fcfg=None, acfg=None):
    rep = json.loads(Path(report_path).read_text(encoding="utf-8"))
    hr = (rep.get("horizons") or {}).get(str(horizon))
    if not hr or hr.get("status") != "completed":
        raise SystemExit(f"horizon {horizon} was not evaluated in {report_path}")
    fcfg, acfg = fcfg or load_config(), acfg or acfg_mod.load()
    sha = config_fingerprint(fcfg, acfg["assessment"])
    if sha != rep["config_sha256"]:
        raise SystemExit("config/forecast.json or config/assessment.json changed since the experiment; re-run it")
    df, manifest = load_export(dataset_dir)
    if manifest.get("dataset_version") != rep["dataset_version"]:
        raise SystemExit("dataset folder does not match the report's dataset_version")
    synthetic = is_synthetic(df, manifest)
    grid, _ = to_grid(df, fcfg, acfg)
    frame, feats = build_frame(grid, fcfg, horizon)
    if feats != rep["features"]:
        raise SystemExit("feature list differs from the report")
    cand, params = hr["best_candidate"], hr["chosen_params"][hr["best_candidate"]]
    model = make_model(cand, params, fcfg["seed"])
    model.fit(frame[feats].to_numpy(dtype=float), frame["y"].to_numpy(dtype=float))
    version = f"b2-{fcfg['target']}-h{horizon}-{rep['dataset_version'][-12:]}-{sha[:8]}"
    meta = {
        "version": version, "status": "candidate",
        "status_reason": "registered; awaiting the evaluation gate (forecast/retrain.py)",
        "target": fcfg["target"], "horizon_minutes": horizon, "predict": fcfg["predict"],
        "candidate": cand, "params": params, "features": feats, "training_config": fcfg,
        "thi_formula": acfg["assessment"]["thi"]["formula"]["expression"],
        "assessment_config_version": acfg["version"], "config_sha256": sha,
        "dataset_version": rep["dataset_version"], "dataset_synthetic": synthetic,
        "metrics": hr["test"][cand],
        "evaluation": {"best_baseline": hr["best_baseline"], "baseline_metrics": hr["test"][hr["best_baseline"]],
                       "test_days": hr["test_days"], "alerts": (hr.get("alerts") or {}).get("models", {}).get(cand)},
        "acceptance": rep.get("acceptance"), "report": str(report_path),
        "fit_on": "all rows (development + test) after the single test evaluation",
        "trained_at": datetime.now(timezone.utc).isoformat(),
        "software": {"python": platform.python_version(), "scikit-learn": sklearn.__version__,
                     "numpy": np.__version__, "pandas": pd.__version__},
    }
    root = Path(registry_root)
    root.mkdir(parents=True, exist_ok=True)
    final = root / version
    if final.exists():
        raise SystemExit(f"{final} already exists; versions are immutable")
    tmp = Path(tempfile.mkdtemp(prefix=f".{version}-", dir=root))
    try:
        joblib.dump(model, tmp / "model.joblib")
        (tmp / "metadata.json").write_text(json.dumps(meta, indent=2, default=str), encoding="utf-8")
        os.replace(tmp, final)
    except BaseException:
        shutil.rmtree(tmp, ignore_errors=True)
        raise
    return final, meta


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--report", required=True)
    p.add_argument("--dataset", required=True)
    p.add_argument("--horizon", type=int, required=True)
    p.add_argument("--registry", default=str(ROOT / "models" / "registry"))
    a = p.parse_args(argv)
    final, meta = register(a.report, a.dataset, a.horizon, a.registry)
    print(f"registered {meta['version']} status={meta['status']} ({meta['status_reason']}) at {final}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
