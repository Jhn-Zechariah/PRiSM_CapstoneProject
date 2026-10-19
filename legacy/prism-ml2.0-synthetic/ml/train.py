"""Trains both Decision Trees.  Run:  python -m ml.train"""
import json
import joblib
import numpy as np
import pandas as pd
import sklearn
from sklearn.model_selection import train_test_split, GridSearchCV
from sklearn.tree import DecisionTreeClassifier, export_text
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score, f1_score
from ml.features import (FARM_FEATURES, FARM_ABLATION_DROP, PIG_FEATURES, PIG_ABLATION_DROP)

PARAMS = {"max_depth": [2, 3, 4, 5, 6], "min_samples_leaf": [5, 10, 20]}
# the ablation tree has to approximate the rule from raw inputs, so it may grow deeper
PARAMS_ABLATION = {"max_depth": [4, 6, 8, 10, 12], "min_samples_leaf": [5, 10, 20]}


def fit(df, features, target, params=PARAMS):
    X_tr, X_te, y_tr, y_te = train_test_split(df[features], df[target], test_size=0.2,
                                              stratify=df[target], random_state=42)
    grid = GridSearchCV(DecisionTreeClassifier(class_weight="balanced", random_state=42),
                        params, cv=5, scoring="f1_macro")
    grid.fit(X_tr, y_tr)
    return grid, X_tr, X_te, y_tr, y_te


def run(name, csv, features, target, ablation_drop):
    print(f"\n{'=' * 70}\n{name.upper()}\n{'=' * 70}")
    df = pd.read_csv(csv)
    grid, X_tr, X_te, y_tr, y_te = fit(df, features, target)
    model = grid.best_estimator_
    pred = model.predict(X_te)
    acc, f1 = accuracy_score(y_te, pred), f1_score(y_te, pred, average="macro")
    print("best params:", grid.best_params_)
    print(f"test accuracy = {acc:.4f} | macro-F1 = {f1:.4f}")
    print(classification_report(y_te, pred, digits=3))
    print("confusion matrix (rows = true, cols = predicted); classes:", list(model.classes_))
    print(confusion_matrix(y_te, pred, labels=model.classes_))
    print("feature importances:", dict(zip(features, model.feature_importances_.round(3))))
    print(export_text(model, feature_names=features))

    # ---- ablation: remove the features that directly encode the labelling rule ----
    reduced = [f for f in features if f not in ablation_drop]
    g2, _, X_te2, _, y_te2 = fit(df, reduced, target, PARAMS_ABLATION)
    p2 = g2.best_estimator_.predict(X_te2)
    acc2, f12 = accuracy_score(y_te2, p2), f1_score(y_te2, p2, average="macro")
    print(f"[ABLATION] without {ablation_drop}: accuracy = {acc2:.4f} | macro-F1 = {f12:.4f}")

    # ---- optional tree figure for the paper ----
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from sklearn.tree import plot_tree
        plt.figure(figsize=(18, 8))
        plot_tree(model, feature_names=features, class_names=list(model.classes_),
                  filled=True, rounded=True, fontsize=8)
        plt.savefig(f"models/{name}_tree.png", dpi=150, bbox_inches="tight")
        plt.close()
    except ImportError:
        print("(matplotlib not installed - skipping tree figure)")

    joblib.dump(model, f"models/{name}.pkl")
    meta = {"features": features, "classes": [str(c) for c in model.classes_],
            "metrics": {"accuracy": round(acc, 4), "macro_f1": round(f1, 4),
                        "ablation_accuracy": round(acc2, 4), "ablation_macro_f1": round(f12, 4),
                        "ablation_dropped": ablation_drop},
            "best_params": grid.best_params_,
            "versions": {"scikit-learn": sklearn.__version__, "numpy": np.__version__,
                         "pandas": pd.__version__, "joblib": joblib.__version__}}
    json.dump(meta, open(f"models/{name}_meta.json", "w"), indent=2)
    return meta["versions"]


v = run("farm_model", "data/farm_dataset.csv", FARM_FEATURES, "status", FARM_ABLATION_DROP)
run("pig_growth_model", "data/pig_growth_dataset.csv", PIG_FEATURES, "growth_status", PIG_ABLATION_DROP)

print("\nPin these versions in requirements.txt (the API must use the same ones):")
for k, ver in v.items():
    print(f"  {k}=={ver}")
