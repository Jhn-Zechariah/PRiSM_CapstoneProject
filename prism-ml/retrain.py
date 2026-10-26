"""Run a retraining phase end to end, archiving the previous model for rollback.

    python retrain.py --phase 1          # synthetic only -> deploy as prototype
    python retrain.py --phase 2          # ~1-2 weeks real data: combined training, test on latest real days
    python retrain.py --phase 3          # 2-3+ weeks real data: real only vs synthetic-trained, keep the better
    python retrain.py --list             # show archived models
    python retrain.py --rollback models/archive/model_....joblib

Run `python export_firestore.py` first for phases 2 and 3. The frozen real hold-out
block (models/real_holdout.json) is never used for training in any phase.
"""
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

from common import ARCHIVE_DIR, CURRENT_MODEL_PATH, REPORTS_DIR, load_config
from datasets import build_splits, load_real_frame, local_day
import model_io
from evaluate import predictions_frame


def holdout_mae(bundle: dict, test, cfg) -> float:
    p = predictions_frame(bundle, test, cfg)
    return float(np.mean([np.mean(np.abs(p[f"pred_{h}"] - p[f"actual_{h}"])) for h in cfg["features"]["horizons_min"]]))


def real_days(cfg) -> int:
    frame = load_real_frame(cfg)
    if frame is None:
        return 0
    return len(set(local_day(frame[~frame["missing"]].index, cfg)))


def latest_synthetic_model():
    paths = [CURRENT_MODEL_PATH] + sorted(ARCHIVE_DIR.glob("*.joblib"), reverse=True) if ARCHIVE_DIR.exists() \
        else [CURRENT_MODEL_PATH]
    for p in paths:
        if p.exists() and model_io.load(p).get("synthetic_only"):
            return p
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--phase", type=int, choices=[1, 2, 3])
    ap.add_argument("--force", action="store_true", help="promote the new model even if it is not better")
    ap.add_argument("--rollback", help="re-install an archived model as current")
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    cfg = load_config()

    if a.list:
        for p in sorted(ARCHIVE_DIR.glob("*.joblib")) if ARCHIVE_DIR.exists() else []:
            print(p.name)
        return
    if a.rollback:
        archived = model_io.promote(Path(a.rollback))
        print(f"Rolled back to {a.rollback} (previous current archived as {archived})")
        return
    if not a.phase:
        ap.error("choose --phase, --list or --rollback")

    from train import train
    report = {"phase": a.phase, "run_at": datetime.now(timezone.utc).isoformat()}

    if a.phase == 1:
        path, bundle = train("synthetic", cfg)
        archived = model_io.promote(path)
        report.update(promoted=str(path), archived_previous=str(archived) if archived else None)
    else:
        need = cfg["training"]["min_real_days_phase2" if a.phase == 2 else "min_real_days_phase3"]
        have = real_days(cfg)
        if have < need:
            raise SystemExit(f"Phase {a.phase} needs at least {need} days of real data; found {have}. "
                             "Run export_firestore.py, or wait for more data.")
        data = "combined" if a.phase == 2 else "real"
        path, bundle = train(data, cfg)
        test = build_splits("real", cfg)["test"]       # the frozen real hold-out block
        contenders = {"new_" + data: (path, bundle)}
        if CURRENT_MODEL_PATH.exists():
            contenders["current_deployed"] = (CURRENT_MODEL_PATH, model_io.load(CURRENT_MODEL_PATH))
        syn = latest_synthetic_model()
        if a.phase == 3 and syn is not None:
            contenders["synthetic_trained"] = (syn, model_io.load(syn))
        scores = {k: round(holdout_mae(b, test, cfg), 4) for k, (_, b) in contenders.items()}
        best = min(scores, key=scores.get)
        report.update(holdout_days=sorted(set(test["day"])), holdout_mean_mae=scores,
                      winner=best, winner_version=contenders[best][1]["version"])
        print("Hold-out mean MAE (t+15, t+30):", scores, "->", best)
        if best == "new_" + data or a.force:
            archived = model_io.promote(path)
            report.update(promoted=str(path), archived_previous=str(archived) if archived else None)
            print(f"Promoted {path.name}")
        elif best == "synthetic_trained" and contenders[best][0] != CURRENT_MODEL_PATH:
            archived = model_io.promote(contenders[best][0])
            report.update(promoted=str(contenders[best][0]), archived_previous=str(archived))
            print(f"Re-installed synthetic-trained model {contenders[best][0].name}")
        else:
            report["promoted"] = None
            print("Kept the current model (it scored best on the real hold-out block).")

    REPORTS_DIR.mkdir(exist_ok=True)
    out = REPORTS_DIR / f"retrain_phase{a.phase}_{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.json"
    out.write_text(json.dumps(report, indent=2, default=str))
    print(f"Saved {out}")


if __name__ == "__main__":
    main()
