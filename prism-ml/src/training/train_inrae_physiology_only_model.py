"""
Train a genuine machine-learning model using ONLY physiological
measurements from the public INRAE swine dataset.

This experiment predicts the genuine experimental thermal state:

    - Thermoneutralité
    - Montée température
    - Stress thermique

IMPORTANT:
- Uses only genuine public experimental data.
- No synthetic data.
- No synthetic labels.
- No deterministic prediction rules.
- Uses pig-grouped cross-validation.
- Experimental stage is excluded.
- Environmental temperature is excluded.
- Age and ADFI are excluded.
- Pig identity is excluded from ML features.
- Experimental schedule variables are excluded.
- This is NOT the final PRISM risk model.

Purpose:
    Determine how much predictive information is available from
    internal/core body-temperature measurements alone.

This is an ablation experiment and should be compared with:

    Model A:
        physiology + age + ADFI + stage

    Model B:
        physiology + age + ADFI

    Model C:
        physiology only   <-- this script
"""

from pathlib import Path

import joblib
import pandas as pd

from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
)
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.pipeline import Pipeline


# ============================================================
# PATHS
# ============================================================

PROJECT_ROOT = Path(__file__).resolve().parents[2]

INPUT_FILE = (
    PROJECT_ROOT
    / "data"
    / "processed"
    / "inrae"
    / "inrae_ml_features_30min.csv"
)

MODEL_DIR = PROJECT_ROOT / "models"
REPORT_DIR = PROJECT_ROOT / "reports"

MODEL_FILE = (
    MODEL_DIR
    / "inrae_public_random_forest_physiology_only.joblib"
)

CV_RESULTS_FILE = (
    REPORT_DIR
    / "inrae_public_physiology_only_grouped_cv_results.csv"
)

CLASSIFICATION_FILE = (
    REPORT_DIR
    / "inrae_public_physiology_only_classification_report.csv"
)

CONFUSION_FILE = (
    REPORT_DIR
    / "inrae_public_physiology_only_confusion_matrix.csv"
)

FEATURE_IMPORTANCE_FILE = (
    REPORT_DIR
    / "inrae_public_physiology_only_feature_importance.csv"
)


# ============================================================
# EXPERIMENT DEFINITION
# ============================================================

TARGET_COLUMN = "periode"
GROUP_COLUMN = "porc"


# ============================================================
# PHYSIOLOGICAL FEATURES ONLY
# ============================================================

PHYSIOLOGICAL_FEATURES = [
    "T_IM_mean",
    "T_IM_std",
    "T_IM_min",
    "T_IM_max",
    "T_IM_range",
    "T_IM_change",
    "T_IM_abs_change",
    "T_IM_change_direction",
    "T_IM_rolling_mean_3",
    "T_IM_rolling_std_3",
]


# These variables are deliberately excluded because this experiment
# is specifically measuring the predictive value of physiological
# internal body-temperature measurements alone.
#
# stage_mean:
#     Experimental-stage/protocol proxy.
#
# T:
#     Environmental temperature directly associated with the
#     experimental heat manipulation.
#
# age_mean:
#     Biological/context variable, excluded for this ablation.
#
# ADFI_mean / ADFI_std:
#     Feeding/context variables, excluded for this ablation.
#
# datetime / schedule fields:
#     Experimental timing information.
#
# id_challenge / ordre_challenge / porc:
#     Experimental or animal identifiers.
#
# source_dataset:
#     Dataset identity.

FORBIDDEN_FEATURES = [
    "stage_mean",
    "T",
    "age_mean",
    "ADFI_mean",
    "ADFI_std",
    "datetime",
    "date_stress",
    "jour_debut_stress",
    "temps_relatif_jour",
    "id_challenge",
    "ordre_challenge",
    "porc",
    "source_dataset",
]


FEATURE_COLUMNS = PHYSIOLOGICAL_FEATURES


EXPECTED_TARGETS = [
    "Thermoneutralité",
    "Montée température",
    "Stress thermique",
]


# ============================================================
# MODEL
# ============================================================

def build_model():
    """
    Build the genuine machine-learning pipeline.

    Missing physiological measurements are handled with median
    imputation.

    The classifier is a Random Forest.

    No deterministic rules are used.
    """

    return Pipeline(
        steps=[
            (
                "imputer",
                SimpleImputer(
                    strategy="median"
                ),
            ),
            (
                "classifier",
                RandomForestClassifier(
                    n_estimators=400,
                    class_weight="balanced",
                    random_state=42,
                    n_jobs=-1,
                ),
            ),
        ]
    )


# ============================================================
# MAIN
# ============================================================

def main():

    print("=" * 78)
    print(
        "INRAE PUBLIC PHYSIOLOGY-ONLY ML MODEL"
    )
    print("=" * 78)
    print()

    print(
        "This model predicts genuine experimental thermal state"
    )

    print(
        "using ONLY internal/core body-temperature measurements."
    )

    print()

    print(
        "Excluded:"
    )
    print(
        "  - experimental stage"
    )
    print(
        "  - environmental temperature"
    )
    print(
        "  - age"
    )
    print(
        "  - ADFI"
    )
    print(
        "  - experimental schedule"
    )
    print(
        "  - pig identity"
    )

    print()

    print(
        "This is NOT the final PRISM risk model."
    )

    print()

    MODEL_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    REPORT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )


    # ========================================================
    # 1. LOAD DATA
    # ========================================================

    print(
        "[1/9] Loading engineered INRAE dataset..."
    )

    if not INPUT_FILE.exists():
        raise FileNotFoundError(
            "Input dataset not found:\n"
            f"{INPUT_FILE}"
        )

    df = pd.read_csv(
        INPUT_FILE
    )

    print(
        f"Rows    : {len(df):,}"
    )

    print(
        f"Columns : {len(df.columns)}"
    )

    print()


    # ========================================================
    # 2. VALIDATE TARGET
    # ========================================================

    print(
        "[2/9] Validating target..."
    )

    if TARGET_COLUMN not in df.columns:
        raise ValueError(
            f"Target column '{TARGET_COLUMN}' "
            "was not found."
        )

    if GROUP_COLUMN not in df.columns:
        raise ValueError(
            f"Grouping column '{GROUP_COLUMN}' "
            "was not found."
        )

    df = df.dropna(
        subset=[
            TARGET_COLUMN,
            GROUP_COLUMN,
        ]
    ).copy()

    unexpected_targets = sorted(
        set(
            df[TARGET_COLUMN]
            .dropna()
            .unique()
        )
        - set(EXPECTED_TARGETS)
    )

    if unexpected_targets:
        raise ValueError(
            "Unexpected target classes found:\n"
            f"{unexpected_targets}"
        )

    print(
        "Target classes:"
    )

    print(
        df[TARGET_COLUMN]
        .value_counts()
    )

    print()


    # ========================================================
    # 3. VALIDATE PHYSIOLOGICAL FEATURES
    # ========================================================

    print(
        "[3/9] Validating physiological feature set..."
    )

    missing_features = [
        feature
        for feature in FEATURE_COLUMNS
        if feature not in df.columns
    ]

    if missing_features:
        raise ValueError(
            "Required physiological features "
            "are missing:\n"
            + "\n".join(
                f"  - {feature}"
                for feature in missing_features
            )
        )

    forbidden_used = [
        feature
        for feature in FORBIDDEN_FEATURES
        if feature in FEATURE_COLUMNS
    ]

    if forbidden_used:
        raise RuntimeError(
            "Forbidden feature(s) accidentally "
            "included in the ML matrix:\n"
            + "\n".join(
                f"  - {feature}"
                for feature in forbidden_used
            )
        )

    print(
        f"Physiological features: "
        f"{len(PHYSIOLOGICAL_FEATURES)}"
    )

    print(
        f"Total ML features: "
        f"{len(FEATURE_COLUMNS)}"
    )

    print()

    print(
        "Features:"
    )

    for feature in FEATURE_COLUMNS:
        print(
            f"  - {feature}"
        )

    print()

    print(
        "Explicitly excluded:"
    )

    print(
        "  - stage_mean"
    )

    print(
        "  - environmental T"
    )

    print(
        "  - age_mean"
    )

    print(
        "  - ADFI_mean"
    )

    print(
        "  - ADFI_std"
    )

    print(
        "  - experimental schedule variables"
    )

    print(
        "  - challenge identifiers"
    )

    print(
        "  - pig identity"
    )

    print()


    # ========================================================
    # 4. PREPARE ML MATRIX
    # ========================================================

    print(
        "[4/9] Preparing ML matrix..."
    )

    X = df[
        FEATURE_COLUMNS
    ].copy()

    y = df[
        TARGET_COLUMN
    ].copy()

    groups = df[
        GROUP_COLUMN
    ].copy()

    print(
        f"Training rows: {len(X):,}"
    )

    print(
        f"Unique pigs: {groups.nunique():,}"
    )

    missing_values = int(
        X.isna()
        .sum()
        .sum()
    )

    print(
        f"Missing feature values: "
        f"{missing_values:,}"
    )

    print()


    # ========================================================
    # 5. BUILD ML PIPELINE
    # ========================================================

    print(
        "[5/9] Building ML pipeline..."
    )

    pipeline = build_model()

    print()


    # ========================================================
    # 6. GROUPED CROSS-VALIDATION
    # ========================================================

    print(
        "[6/9] Running grouped cross-validation..."
    )

    print()

    cv = StratifiedGroupKFold(
        n_splits=5,
        shuffle=True,
        random_state=42,
    )

    fold_results = []

    oof_predictions = pd.Series(
        index=df.index,
        dtype="object",
    )

    for fold_number, (
        train_idx,
        validation_idx,
    ) in enumerate(
        cv.split(
            X,
            y,
            groups=groups,
        ),
        start=1,
    ):

        X_train = X.iloc[
            train_idx
        ]

        X_validation = X.iloc[
            validation_idx
        ]

        y_train = y.iloc[
            train_idx
        ]

        y_validation = y.iloc[
            validation_idx
        ]

        train_groups = groups.iloc[
            train_idx
        ]

        validation_groups = groups.iloc[
            validation_idx
        ]

        print(
            f"Fold {fold_number}"
        )

        print(
            f"  Training rows   : "
            f"{len(train_idx):,}"
        )

        print(
            f"  Validation rows : "
            f"{len(validation_idx):,}"
        )

        print(
            f"  Training pigs   : "
            f"{train_groups.nunique():,}"
        )

        print(
            f"  Validation pigs : "
            f"{validation_groups.nunique():,}"
        )

        print(
            "  Validation pigs:"
        )

        validation_pigs = sorted(
            validation_groups.unique()
        )

        print(
            "  "
            + ", ".join(
                str(pig)
                for pig in validation_pigs
            )
        )

        fold_model = build_model()

        fold_model.fit(
            X_train,
            y_train,
        )

        predictions = fold_model.predict(
            X_validation
        )

        oof_predictions.iloc[
            validation_idx
        ] = predictions

        accuracy = accuracy_score(
            y_validation,
            predictions,
        )

        balanced_accuracy = (
            balanced_accuracy_score(
                y_validation,
                predictions,
            )
        )

        macro_precision = (
            precision_score(
                y_validation,
                predictions,
                average="macro",
                zero_division=0,
            )
        )

        macro_recall = (
            recall_score(
                y_validation,
                predictions,
                average="macro",
                zero_division=0,
            )
        )

        macro_f1 = (
            f1_score(
                y_validation,
                predictions,
                average="macro",
                zero_division=0,
            )
        )

        print(
            f"  Accuracy          : "
            f"{accuracy:.6f}"
        )

        print(
            f"  Balanced accuracy : "
            f"{balanced_accuracy:.6f}"
        )

        print(
            f"  Macro precision   : "
            f"{macro_precision:.6f}"
        )

        print(
            f"  Macro recall      : "
            f"{macro_recall:.6f}"
        )

        print(
            f"  Macro F1          : "
            f"{macro_f1:.6f}"
        )

        print()

        fold_results.append(
            {
                "fold": fold_number,
                "accuracy": accuracy,
                "balanced_accuracy": balanced_accuracy,
                "macro_precision": macro_precision,
                "macro_recall": macro_recall,
                "macro_f1": macro_f1,
                "training_rows": len(
                    train_idx
                ),
                "validation_rows": len(
                    validation_idx
                ),
                "training_pigs": (
                    train_groups.nunique()
                ),
                "validation_pigs": (
                    validation_groups.nunique()
                ),
            }
        )


    # ========================================================
    # 7. OUT-OF-FOLD RESULTS
    # ========================================================

    print(
        "[7/9] Calculating out-of-fold results..."
    )

    print()

    fold_results_df = pd.DataFrame(
        fold_results
    )

    print(
        "Fold results:"
    )

    print(
        fold_results_df.to_string(
            index=False,
            float_format=lambda value:
                f"{value:.6f}",
        )
    )

    print()

    metric_columns = [
        "accuracy",
        "balanced_accuracy",
        "macro_precision",
        "macro_recall",
        "macro_f1",
    ]

    print(
        "Mean ± standard deviation:"
    )

    for metric in metric_columns:

        mean_value = (
            fold_results_df[
                metric
            ].mean()
        )

        std_value = (
            fold_results_df[
                metric
            ].std()
        )

        print(
            f"  {metric:<20}: "
            f"{mean_value:.6f} ± "
            f"{std_value:.6f}"
        )

    print()


    # ========================================================
    # OOF CLASSIFICATION REPORT
    # ========================================================

    valid_oof_mask = (
        oof_predictions.notna()
    )

    y_oof = y.loc[
        valid_oof_mask
    ]

    predictions_oof = (
        oof_predictions.loc[
            valid_oof_mask
        ]
    )

    report_dict = classification_report(
        y_oof,
        predictions_oof,
        labels=EXPECTED_TARGETS,
        output_dict=True,
        zero_division=0,
    )

    report_df = pd.DataFrame(
        report_dict
    ).transpose()

    print(
        "Out-of-fold classification report:"
    )

    print(
        report_df.to_string(
            float_format=lambda value:
                f"{value:.6f}"
        )
    )

    print()


    # ========================================================
    # OOF CONFUSION MATRIX
    # ========================================================

    confusion = confusion_matrix(
        y_oof,
        predictions_oof,
        labels=EXPECTED_TARGETS,
    )

    confusion_df = pd.DataFrame(
        confusion,
        index=[
            f"actual_{label}"
            for label in EXPECTED_TARGETS
        ],
        columns=[
            f"predicted_{label}"
            for label in EXPECTED_TARGETS
        ],
    )

    print(
        "Out-of-fold confusion matrix:"
    )

    print(
        confusion_df.to_string()
    )

    print()


    # ========================================================
    # 8. TRAIN FINAL PUBLIC-DATA MODEL
    # ========================================================

    print(
        "[8/9] Training final physiology-only "
        "public-data model..."
    )

    final_model = build_model()

    final_model.fit(
        X,
        y,
    )

    classifier = (
        final_model.named_steps[
            "classifier"
        ]
    )

    importances = (
        classifier.feature_importances_
    )

    feature_importance_df = (
        pd.DataFrame(
            {
                "feature": FEATURE_COLUMNS,
                "importance": importances,
            }
        )
        .sort_values(
            "importance",
            ascending=False,
        )
        .reset_index(
            drop=True
        )
    )

    print()

    print(
        "Feature importances:"
    )

    print(
        feature_importance_df.to_string(
            index=False,
            float_format=lambda value:
                f"{value:.6f}",
        )
    )

    print()


    # ========================================================
    # 9. SAVE MODEL AND REPORTS
    # ========================================================

    print(
        "[9/9] Saving model and reports..."
    )

    metadata = {
        "dataset": (
            "INRAE public experimental "
            "swine dataset"
        ),
        "task": (
            "Experimental thermal-state "
            "classification"
        ),
        "experiment": (
            "Physiology-only ablation"
        ),
        "target_column": TARGET_COLUMN,
        "group_column": GROUP_COLUMN,
        "feature_columns": FEATURE_COLUMNS,
        "physiological_features": (
            PHYSIOLOGICAL_FEATURES
        ),
        "forbidden_features": (
            FORBIDDEN_FEATURES
        ),
        "stage_excluded": True,
        "environmental_temperature_excluded": True,
        "age_excluded": True,
        "ADFI_excluded": True,
        "synthetic_data": False,
        "synthetic_labels": False,
        "deterministic_rules": False,
        "cross_validation": (
            "StratifiedGroupKFold"
        ),
        "n_splits": 5,
        "grouped_by": GROUP_COLUMN,
        "random_state": 42,
    }

    model_package = {
        "model": final_model,
        "metadata": metadata,
    }

    joblib.dump(
        model_package,
        MODEL_FILE,
    )

    fold_results_df.to_csv(
        CV_RESULTS_FILE,
        index=False,
    )

    report_df.to_csv(
        CLASSIFICATION_FILE
    )

    confusion_df.to_csv(
        CONFUSION_FILE
    )

    feature_importance_df.to_csv(
        FEATURE_IMPORTANCE_FILE,
        index=False,
    )

    print()

    print(
        "Model saved:"
    )

    print(
        MODEL_FILE
    )

    print(
        "CV results saved:"
    )

    print(
        CV_RESULTS_FILE
    )

    print(
        "Classification report saved:"
    )

    print(
        CLASSIFICATION_FILE
    )

    print(
        "Confusion matrix saved:"
    )

    print(
        CONFUSION_FILE
    )

    print(
        "Feature importance saved:"
    )

    print(
        FEATURE_IMPORTANCE_FILE
    )

    print()

    print("=" * 78)

    print(
        "INRAE physiology-only ML experiment "
        "completed."
    )

    print("=" * 78)


if __name__ == "__main__":
    main()