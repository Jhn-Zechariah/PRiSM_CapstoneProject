"""Reproducible training pipeline for the current-thermal-status classifier.

Steps: load trusted local labels -> check data requirements -> temporal group hold-out -> grouped CV
model selection (Decision Tree / Random Forest / HistGradientBoosting) -> probability calibration ->
abstention threshold from out-of-fold predictions -> single evaluation on the held-out test set ->
acceptance decision -> register as *candidate* (approval is a separate, manual step).

The pipeline refuses to train when the trusted data are insufficient; it never falls back to
synthetic data or rule-generated labels.
"""
from __future__ import annotations

import json
import platform
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import numpy as np
import pandas as pd
import sklearn
from sklearn.base import clone
from sklearn.calibration import CalibratedClassifierCV
from sklearn.ensemble import HistGradientBoostingClassifier, RandomForestClassifier
from sklearn.model_selection import GridSearchCV
from sklearn.tree import DecisionTreeClassifier

from prism_ml import __version__
from prism_ml.config import REPORTS_DIR, load_config
from prism_ml.data.local_dataset import LocalDataset, load_local_dataset, requirements_report
from prism_ml.data.splits import assert_disjoint, group_cv, temporal_group_split
from prism_ml.features.contract import contract_hash, contract_version, feature_names
from prism_ml.models.evaluate import (abstention_metrics, acceptance_decision, choose_abstention_threshold,
                                      classification_metrics)
from prism_ml.models.registry import ModelRegistry


SKLEARN_SCORING = {"macro_f1": "f1_macro", "balanced_accuracy": "balanced_accuracy"}


class InsufficientTrustedData(RuntimeError):
    def __init__(self, problems: list[str], summary: dict):
        super().__init__("; ".join(problems))
        self.problems = problems
        self.summary = summary


@dataclass
class TrainingResult:
    model_id: str
    acceptance: dict
    test_metrics: dict
    report_path: Path


def _candidates(seed: int) -> dict:
    return {
        "decision_tree": DecisionTreeClassifier(class_weight="balanced", random_state=seed),
        "random_forest": RandomForestClassifier(class_weight="balanced", random_state=seed, n_jobs=1),
        "hist_gradient_boosting": HistGradientBoostingClassifier(class_weight="balanced", random_state=seed),
    }


def _calibrated(estimator, X: pd.DataFrame, y: pd.Series, groups: pd.Series, seed: int, method: str):
    n = min(3, groups.nunique())
    splits = list(group_cv(n, seed).split(X, y, groups))
    return CalibratedClassifierCV(clone(estimator), method=method, cv=splits)


def _oof_proba(estimator, X, y, groups, classes, seed, n_splits, method) -> np.ndarray:
    proba = np.zeros((len(X), len(classes)))
    for tr, va in group_cv(n_splits, seed).split(X, y, groups):
        model = _calibrated(estimator, X.iloc[tr], y.iloc[tr], groups.iloc[tr], seed, method)
        model.fit(X.iloc[tr], y.iloc[tr])
        p = model.predict_proba(X.iloc[va])
        order = [list(model.classes_).index(c) for c in classes]
        proba[va] = p[:, order]
    return proba


def train(dataset: Optional[LocalDataset] = None, registry: Optional[ModelRegistry] = None,
          model_id: Optional[str] = None, reports_dir: Path = REPORTS_DIR) -> TrainingResult:
    cfg = load_config("training")
    seed, classes = cfg["random_seed"], cfg["classes"]
    ds = dataset if dataset is not None else load_local_dataset()
    problems = requirements_report(ds)
    if problems:
        raise InsufficientTrustedData(problems, ds.summary)

    frame = ds.frame.reset_index(drop=True)
    group_col = cfg["group_column"]
    train_idx, test_idx = temporal_group_split(frame, group_col, "window_start", cfg["test_split"]["test_fraction_of_groups"])
    assert_disjoint(frame, train_idx, test_idx, group_col)
    feats = feature_names()
    X_tr, y_tr, g_tr = frame.loc[train_idx, feats], frame.loc[train_idx, "status"], frame.loc[train_idx, group_col]
    X_te, y_te = frame.loc[test_idx, feats], frame.loc[test_idx, "status"]

    # --- model selection on training sessions only ------------------------------------------------
    cv_results = {}
    best_name, best_score, best_est = None, -np.inf, None
    for name, est in _candidates(seed).items():
        grid = GridSearchCV(est, cfg["candidates"][name], scoring=SKLEARN_SCORING[cfg["selection_metric"]],
                            cv=group_cv(cfg["cv"]["n_splits"], seed), n_jobs=1, error_score="raise")
        grid.fit(X_tr, y_tr, groups=g_tr)
        cv_results[name] = {"best_params": grid.best_params_, "cv_macro_f1": float(grid.best_score_),
                            "cv_macro_f1_std": float(grid.cv_results_["std_test_score"][grid.best_index_])}
        if grid.best_score_ > best_score:
            best_name, best_score, best_est = name, grid.best_score_, grid.best_estimator_

    method = cfg["calibration"]["method"]
    # --- abstention threshold from out-of-fold (validation) predictions --------------------------
    oof = _oof_proba(best_est, X_tr, y_tr, g_tr, classes, seed, cfg["cv"]["n_splits"], method)
    abstention = choose_abstention_threshold(y_tr, oof, classes)

    # --- final fit on all training sessions, single evaluation on the hold-out -------------------
    final = _calibrated(best_est, X_tr, y_tr, g_tr, seed, method)
    final.fit(X_tr, y_tr)
    order = [list(final.classes_).index(c) for c in classes]
    proba_te = final.predict_proba(X_te)[:, order]
    pred_te = np.asarray(classes)[proba_te.argmax(axis=1)]
    test_metrics = classification_metrics(y_te, pred_te, classes, proba_te)
    if abstention is not None:
        test_metrics["abstention"] = abstention_metrics(y_te, proba_te, classes, abstention["threshold"])

    majority = Counter(y_tr).most_common(1)[0][0]
    baseline = classification_metrics(y_te, [majority] * len(y_te), classes)
    test_sessions = int(frame.loc[test_idx, group_col].nunique())
    by_farm = {}
    for farm, idx in frame.loc[test_idx].groupby("farm_id").groups.items():
        pos = [list(test_idx).index(i) for i in idx]
        by_farm[str(farm)] = classification_metrics(y_te.iloc[pos], pred_te[pos], classes)["macro_f1"]
    acceptance = acceptance_decision(test_metrics, baseline["macro_f1"], test_sessions, abstention)

    now = datetime.now(timezone.utc)
    model_id = model_id or f"thermal-status-{now:%Y%m%d-%H%M%S}"
    ranges = {f: [float(X_tr[f].min()), float(X_tr[f].max())] for f in feats}
    metadata = {
        "model_id": model_id,
        "task": "current thermal-status classification (not forecasting)",
        "classes": classes,
        "algorithm": best_name,
        "calibration": method,
        "feature_contract_version": contract_version(),
        "feature_contract_sha256": contract_hash(),
        "features": feats,
        "validated_feature_ranges": ranges,
        "class_feature_medians": {str(k): {f: float(v) for f, v in row.items()} for k, row in
                                  frame.loc[train_idx].groupby("status")[feats].median().iterrows()},
        "abstention_threshold": abstention["threshold"] if abstention else None,
        "calibration_profiles": sorted(set(frame.loc[train_idx, "calibration_profile"]) - {""}),
        "training_data": {**ds.summary, "train_readings": int(len(train_idx)), "test_readings": int(len(test_idx)),
                          "train_sessions": int(g_tr.nunique()), "test_sessions": test_sessions},
        "random_seed": seed,
        "created_at": now.isoformat(timespec="seconds"),
        "versions": {"prism_ml": __version__, "python": platform.python_version(), "scikit-learn": sklearn.__version__,
                     "numpy": np.__version__, "pandas": pd.__version__},
        "training_config": cfg,
    }
    evaluation = {"model_id": model_id, "evaluated_on": "held-out temporal test sessions", "cv_model_selection": cv_results,
                  "selected": best_name, "validation_abstention": abstention, "test": test_metrics,
                  "majority_baseline_test": {"class": majority, "macro_f1": baseline["macro_f1"]},
                  "test_macro_f1_by_farm": by_farm, "acceptance": acceptance}
    reg = registry or ModelRegistry()
    reg.register(model_id, final, metadata, evaluation)

    reports_dir.mkdir(parents=True, exist_ok=True)
    report_path = reports_dir / f"training_{model_id}.json"
    report_path.write_text(json.dumps({"metadata": metadata, "evaluation": evaluation}, indent=2, default=str),
                           encoding="utf-8")
    return TrainingResult(model_id, acceptance, test_metrics, report_path)
