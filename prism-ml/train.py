"""Train and select the pig-surface-temperature forecaster.

    python train.py --data synthetic             # Phase 1
    python train.py --data combined              # Phase 2 (real rows weighted x sample_weight_real)
    python train.py --data real                  # Phase 3
    python train.py --data synthetic --promote   # also install as models/current_model.joblib

Candidates: persistence baseline, Ridge, Random Forest, gradient boosting (LightGBM,
or HistGradientBoostingRegressor if LightGBM is missing). Each is tuned with
TimeSeriesSplit on the training days, compared on the validation days, and the one
with the lowest mean validation MAE is refit on train+validation and tested once.
"""
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
import sklearn
from sklearn.ensemble import HistGradientBoostingRegressor, RandomForestRegressor
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV, TimeSeriesSplit
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

from common import MODELS_DIR, REPORTS_DIR, bands, envelope, load_config
from datasets import build_splits, load_real_frame, supervised
from evaluate import evaluate
from features import feature_columns
import model_io
from sanity import envelope_warnings, range_report

try:
    from lightgbm import LGBMRegressor
    HAVE_LGBM = True
except ImportError:      # pragma: no cover
    HAVE_LGBM = False

TUNE_STRIDE = 3      # tune on every 3rd minute: neighbouring minutes are nearly identical


def candidates(seed: int) -> dict:
    """name -> (estimator, param grid, sample-weight fit-param name). None estimator = persistence."""
    c = {
        "persistence": (None, None, None),
        "ridge": (Pipeline([("scale", StandardScaler()), ("ridge", Ridge())]),
                  {"ridge__alpha": [0.1, 1.0, 10.0, 100.0]}, "ridge__sample_weight"),
        "random_forest": (RandomForestRegressor(n_estimators=120, min_samples_leaf=20, max_features=0.5,
                                                max_samples=0.5, n_jobs=-1, random_state=seed),
                          {"max_depth": [10, 16]}, "sample_weight"),
    }
    if HAVE_LGBM:
        c["lightgbm"] = (LGBMRegressor(n_estimators=400, learning_rate=0.05, min_child_samples=40,
                                       subsample=0.8, subsample_freq=1, colsample_bytree=0.8,
                                       random_state=seed, verbose=-1, n_jobs=-1),
                         {"num_leaves": [15, 31]}, "sample_weight")
    else:
        c["hist_gradient_boosting"] = (HistGradientBoostingRegressor(max_iter=400, learning_rate=0.05,
                                                                     random_state=seed),
                                       {"max_leaf_nodes": [15, 31]}, "sample_weight")
    return c


def _versions() -> dict:
    from importlib.metadata import PackageNotFoundError, version
    out = {}
    for pkg in ("scikit-learn", "numpy", "pandas", "joblib", "lightgbm"):
        try:
            out[pkg] = version(pkg)
        except PackageNotFoundError:
            out[pkg] = None
    return out


def _fit(est, X, y, w, wname):
    return est.fit(X, y, **({wname: w} if wname else {}))


def tune(est, grid, wname, X, y, w, n_splits):
    idx = np.arange(0, len(X), TUNE_STRIDE)
    gs = GridSearchCV(sklearn.clone(est), grid, cv=TimeSeriesSplit(n_splits=n_splits),
                      scoring="neg_mean_absolute_error", n_jobs=1)
    gs.fit(X.iloc[idx], y.iloc[idx], **({wname: w[idx]} if wname else {}))
    return gs.best_params_


def train(data: str, cfg: dict | None = None, out_dir: Path = MODELS_DIR / "candidates",
          report: bool = True, verbose: bool = True) -> tuple[Path, dict]:
    cfg = cfg or load_config()
    seed = cfg["project"]["random_seed"]
    horizons = cfg["features"]["horizons_min"]
    cols = feature_columns(cfg)
    log = print if verbose else (lambda *a, **k: None)

    sp = build_splits(data, cfg)
    tr, va, te = sp["train"], sp["val"], sp["test"]
    w_tr, w_va = sp["weights"]["train"], sp["weights"]["val"]
    log(f"[{data}] rows: train {len(tr):,}  val {len(va):,}  test {len(te):,}")

    # ---- tune + compare on validation ----
    selection = {}
    best_params = {}
    for name, (est, grid, wname) in candidates(seed).items():
        maes = {}
        best_params[name] = {}
        for h in horizons:
            y_tr = tr[f"target_{h}"]
            if est is None:
                pred = np.zeros(len(va))
            else:
                params = tune(est, grid, wname, tr[cols], y_tr, w_tr, cfg["training"]["tscv_splits"])
                best_params[name][h] = params
                model = _fit(sklearn.clone(est).set_params(**params), tr[cols], y_tr, w_tr, wname)
                pred = model.predict(va[cols])
            err = np.abs(pred - va[f"target_{h}"].to_numpy())
            maes[f"t+{h}"] = round(float(np.average(err, weights=w_va)), 4)
        maes["mean"] = round(float(np.mean(list(maes.values()))), 4)
        selection[name] = maes
        log(f"  {name:24s} val MAE  " + "  ".join(f"{k}={v:.4f}" for k, v in maes.items()))
    winner = min(selection, key=lambda n: selection[n]["mean"])
    log(f"  -> selected: {winner}")

    # ---- refit winner on train+val ----
    est, _, wname = candidates(seed)[winner]
    trva = pd.concat([tr, va])
    w_trva = np.concatenate([w_tr, w_va])
    estimators = {}
    for h in horizons:
        if est is None:
            estimators[h] = None
        else:
            m = sklearn.clone(est).set_params(**best_params[winner][h])
            estimators[h] = _fit(m, trva[cols], trva[f"target_{h}"], w_trva, wname)

    now = datetime.now(timezone.utc)
    bundle = {
        "bundle_format": 1,
        "model_name": winner,
        "version": f"{winner}-{data}-{now.strftime('%Y%m%d%H%M')}",
        "data_source": data,
        "synthetic_only": data == "synthetic",
        "trained_at": now.isoformat(),
        "target": "delta",
        "horizons": horizons,
        "feature_columns": cols,
        "estimators": estimators,
        "envelope": envelope(cfg),
        "selection_val_mae": selection,
        "best_params": {k: {str(h): p for h, p in v.items()} for k, v in best_params.items()},
        "days": sp["days"],
        "versions": _versions(),
    }
    path = model_io.save(bundle, out_dir / f"model_{data}_{now.strftime('%Y%m%dT%H%M%SZ')}.joblib")
    log(f"Saved candidate model -> {path}")

    if report:
        write_report(bundle, data, te, sp, cfg, selection, log)
    return path, bundle


def write_report(bundle, data, test, splits, cfg, selection, log=print):
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d")
    REPORTS_DIR.mkdir(exist_ok=True)
    prefix = REPORTS_DIR / f"{data}_{stamp}"
    label = {"synthetic": "synthetic test days", "real": "real hold-out days",
             "combined": "real hold-out days (combined training)"}[data]
    res = evaluate(bundle, test, cfg, label, prefix)

    all_rows = pd.concat([splits["train"], splits["val"], splits["test"]])
    coverage = {}
    for src, df in all_rows.groupby("source"):
        rep = range_report(df, cfg)
        rep.pop("bands")
        rep["warnings"] = envelope_warnings(rep, cfg, emit=False) if src == "real" else []
        coverage[src] = rep

    transfer = {"status": "not available: no real data exported yet"}
    if data == "synthetic":
        frame = load_real_frame(cfg)
        if frame is not None:
            real_sup = supervised(frame, cfg)
            if len(real_sup):
                transfer = evaluate(bundle, real_sup, cfg, "synthetic-to-real transfer (all real data)",
                                    REPORTS_DIR / f"transfer_{stamp}")

    metrics = {
        "IMPORTANT": (("SYNTHETIC-DATA RESULTS - pipeline sanity check only, NOT real system accuracy. "
                       "Only a held-out real test set is a valid performance claim.")
                      if data == "synthetic" else
                      "Results on the frozen real hold-out block (never used for training)."),
        "data_source": data,
        "model": {k: bundle[k] for k in ("model_name", "version", "trained_at", "target", "horizons")},
        "model_selection_validation_mae": selection,
        "selected_model": bundle["model_name"],
        "test": res,
        "range_coverage": {"bands": bands(cfg), "by_source": coverage},
        "synthetic_to_real_transfer": transfer,
        "feature_columns": bundle["feature_columns"],
    }
    out = REPORTS_DIR / f"metrics_{data}_{stamp}.json"
    out.write_text(json.dumps(metrics, indent=2, default=str))
    log(f"Saved report -> {out}")
    r = res["regression"]
    for h in cfg["features"]["horizons_min"]:
        k = f"t+{h}"
        log(f"  test {k}: MAE {r[k]['mae']:.3f} (persistence {r[k]['baseline_persistence_mae']:.3f})  "
            f"RMSE {r[k]['rmse']:.3f} (persistence {r[k]['baseline_persistence_rmse']:.3f})")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", choices=["synthetic", "real", "combined"], default="synthetic")
    ap.add_argument("--promote", action="store_true",
                    help="archive the current model and install this one as models/current_model.joblib")
    a = ap.parse_args()
    path, _ = train(a.data)
    if a.promote:
        archived = model_io.promote(path)
        print(f"Promoted -> models/current_model.joblib" + (f" (previous archived: {archived})" if archived else ""))


if __name__ == "__main__":
    main()
