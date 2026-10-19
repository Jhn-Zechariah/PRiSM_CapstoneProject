"""Metrics computed on held-out data and the acceptance decision."""
from __future__ import annotations

from typing import Optional

import numpy as np
from sklearn.metrics import (balanced_accuracy_score, classification_report, confusion_matrix, f1_score,
                             recall_score)

from prism_ml.config import load_config

HIGH_RISK, GOOD, NEEDS_ATTENTION = "High Risk", "Good", "Needs Attention"


def multiclass_brier(y_true, proba: np.ndarray, classes: list[str]) -> float:
    onehot = np.array([[1.0 if y == c else 0.0 for c in classes] for y in y_true])
    return float(np.mean(np.sum((proba - onehot) ** 2, axis=1)))


def classification_metrics(y_true, y_pred, classes: list[str], proba: Optional[np.ndarray] = None) -> dict:
    y_true, y_pred = list(y_true), list(y_pred)
    cm = confusion_matrix(y_true, y_pred, labels=classes)
    hr_true = [i for i, y in enumerate(y_true) if y == HIGH_RISK]
    hr_recall = recall_score(y_true, y_pred, labels=[HIGH_RISK], average="macro", zero_division=0)
    good_when_hr = (sum(1 for i in hr_true if y_pred[i] == GOOD) / len(hr_true)) if hr_true else None
    out = {
        "n": len(y_true),
        "class_distribution": {c: int(sum(1 for y in y_true if y == c)) for c in classes},
        "macro_f1": float(f1_score(y_true, y_pred, labels=classes, average="macro", zero_division=0)),
        "balanced_accuracy": float(balanced_accuracy_score(y_true, y_pred)),
        "high_risk_recall": float(hr_recall),
        "high_risk_false_negative_rate": float(1.0 - hr_recall),
        "needs_attention_recall": float(recall_score(y_true, y_pred, labels=[NEEDS_ATTENTION], average="macro",
                                                     zero_division=0)),
        "good_predicted_when_high_risk": good_when_hr,
        "confusion_matrix": {"labels": classes, "rows_true_cols_pred": cm.tolist()},
        "per_class": classification_report(y_true, y_pred, labels=classes, output_dict=True, zero_division=0),
    }
    if proba is not None:
        out["multiclass_brier"] = multiclass_brier(y_true, proba, classes)
    return out


def abstention_metrics(y_true, proba: np.ndarray, classes: list[str], threshold: float) -> dict:
    conf = proba.max(axis=1)
    accepted = conf >= threshold
    y_true = np.asarray(list(y_true))
    pred = np.asarray(classes)[proba.argmax(axis=1)]
    res = {"threshold": threshold, "coverage": float(accepted.mean()) if len(conf) else 0.0}
    if accepted.any():
        res["accepted_macro_f1"] = float(f1_score(y_true[accepted], pred[accepted], labels=classes, average="macro",
                                                  zero_division=0))
    else:
        res["accepted_macro_f1"] = None
    hr = y_true == HIGH_RISK
    # Safety view: a High Risk case is "missed" only if it is shown as a thermal status other than High Risk.
    # Abstained cases are shown as "Uncertain", which is not reassuring.
    res["high_risk_shown_as_lower_status"] = (float(((pred != HIGH_RISK) & accepted & hr).sum() / hr.sum())
                                              if hr.any() else None)
    return res


def choose_abstention_threshold(y_true, proba: np.ndarray, classes: list[str]) -> Optional[dict]:
    cfg = load_config("training")["abstention"]
    for t in cfg["grid"]:
        m = abstention_metrics(y_true, proba, classes, t)
        if m["coverage"] >= cfg["min_coverage"] and (m["accepted_macro_f1"] or 0) >= cfg["target_accepted_macro_f1"]:
            return m
    return None


def acceptance_decision(test_metrics: dict, baseline_macro_f1: float, test_sessions: int,
                        abstention: Optional[dict]) -> dict:
    acc = load_config("acceptance")
    m, d = acc["metrics"], acc["data_requirements"]
    failures = []

    def need(cond, msg):
        if not cond:
            failures.append(msg)

    need(test_sessions >= d["min_test_sessions"], f"test sessions {test_sessions} < {d['min_test_sessions']}")
    for cls, n in test_metrics["class_distribution"].items():
        need(n >= d["min_test_readings_per_class"], f"test readings for '{cls}' {n} < {d['min_test_readings_per_class']}")
    need(test_metrics["high_risk_recall"] >= m["min_high_risk_recall"],
         f"High Risk recall {test_metrics['high_risk_recall']:.3f} < {m['min_high_risk_recall']}")
    need(test_metrics["high_risk_false_negative_rate"] <= m["max_high_risk_false_negative_rate"],
         f"High Risk FNR {test_metrics['high_risk_false_negative_rate']:.3f} > {m['max_high_risk_false_negative_rate']}")
    need(test_metrics["macro_f1"] >= m["min_macro_f1"], f"macro-F1 {test_metrics['macro_f1']:.3f} < {m['min_macro_f1']}")
    need(test_metrics["balanced_accuracy"] >= m["min_balanced_accuracy"],
         f"balanced accuracy {test_metrics['balanced_accuracy']:.3f} < {m['min_balanced_accuracy']}")
    need(test_metrics["needs_attention_recall"] >= m["min_needs_attention_recall"],
         f"Needs Attention recall {test_metrics['needs_attention_recall']:.3f} < {m['min_needs_attention_recall']}")
    g = test_metrics["good_predicted_when_high_risk"]
    need(g is not None and g <= m["max_good_predicted_when_high_risk"],
         f"'Good' shown for High Risk rate {g} > {m['max_good_predicted_when_high_risk']}")
    need(test_metrics["macro_f1"] - baseline_macro_f1 >= m["must_beat_majority_baseline_macro_f1_by"],
         f"macro-F1 margin over majority baseline {test_metrics['macro_f1'] - baseline_macro_f1:.3f} < "
         f"{m['must_beat_majority_baseline_macro_f1_by']}")
    brier = test_metrics.get("multiclass_brier")
    need(brier is not None and brier <= m["max_multiclass_brier"], f"multiclass Brier {brier} > {m['max_multiclass_brier']}")
    need(abstention is not None, "no abstention threshold met the validation targets")
    return {"criteria_version": acc["version"], "passed": not failures, "failures": failures}
