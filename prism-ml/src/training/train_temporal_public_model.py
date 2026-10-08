"""
Train and evaluate a genuine ML model using the temporal HotPig features.

This is a separate experiment from train_public_model.py.

Important:
- Uses only genuine HotPig observations.
- Uses the original experimental condition as the target.
- Does not create synthetic labels.
- Does not use deterministic prediction rules.
- Uses pig_id only for grouped validation.
- Uses StratifiedGroupKFold so observations from the same pig
  are not split between training and validation folds.
"""

from pathlib import Path

import joblib
import numpy as np
import pandas as pd

from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    classification_report,
    confusion_matrix,
    precision_recall_fscore_support,
)
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.pipeline import Pipeline


# =====================================================================
# PATHS
# =====================================================================

PROJECT_ROOT = Path(__file__).resolve().parents[2]

INPUT_FILE = (
    PROJECT_ROOT
    / "data"
    / "processed"
    / "hotpig"
    / "hotpig_temporal_ml_features_5min.csv"
)

MODEL_DIR = PROJECT_ROOT / "models"
REPORT_DIR = PROJECT_ROOT / "reports"

MODEL_FILE = (
    MODEL_DIR
    / "hotpig_temporal_random_forest.joblib"
)

FOLD_RESULTS_FILE = (
    REPORT_DIR
    / "hotpig_temporal_grouped_cv_results.csv"
)

CLASSIFICATION_REPORT_FILE = (
    REPORT_DIR
    / "hotpig_temporal_classification_report.csv"
)

CONFUSION_MATRIX_FILE = (
    REPORT_DIR
    / "hotpig_temporal_confusion_matrix.csv"
)

FEATURE_IMPORTANCE_FILE = (
    REPORT_DIR
    / "hotpig_temporal_feature_importance.csv"
)


# =====================================================================
# CONFIGURATION
# =====================================================================

RANDOM_STATE = 42

N_SPLITS = 5

N_ESTIMATORS = 400

TARGET_COLUMN = "conditions"

GROUP_COLUMN = "pig_id"

METADATA_COLUMNS = {
    TARGET_COLUMN,
    GROUP_COLUMN,
    "window_start",
}


VALID_TARGETS = [
    "HS",
    "TD",
    "TN",
    "TU",
]


# =====================================================================
# MODEL
# =====================================================================

def create_model():

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
                    n_estimators=N_ESTIMATORS,
                    class_weight="balanced",
                    random_state=RANDOM_STATE,
                    n_jobs=-1,
                ),
            ),
        ]
    )


# =====================================================================
# MAIN
# =====================================================================

def main():

    print("=" * 70)
    print("HotPig Temporal Random Forest Training")
    print("=" * 70)

    print(
        f"\nInput file:\n{INPUT_FILE}"
    )

    # -----------------------------------------------------------------
    # LOAD
    # -----------------------------------------------------------------

    print(
        "\n[1/8] Loading temporal feature dataset..."
    )

    if not INPUT_FILE.exists():
        raise FileNotFoundError(
            f"Input file does not exist:\n{INPUT_FILE}"
        )

    df = pd.read_csv(INPUT_FILE)

    print(
        f"Rows    : {len(df):,}"
    )

    print(
        f"Columns : {len(df.columns):,}"
    )

    # -----------------------------------------------------------------
    # VALIDATE TARGET
    # -----------------------------------------------------------------

    print(
        "\n[2/8] Validating target..."
    )

    if TARGET_COLUMN not in df.columns:
        raise ValueError(
            f"Missing target column: "
            f"{TARGET_COLUMN}"
        )

    observed_targets = sorted(
        df[TARGET_COLUMN]
        .dropna()
        .unique()
        .tolist()
    )

    if observed_targets != VALID_TARGETS:
        raise ValueError(
            "Unexpected target classes.\n"
            f"Expected: {VALID_TARGETS}\n"
            f"Found:    {observed_targets}"
        )

    print(
        "Target classes:",
        observed_targets
    )

    print("\nTarget distribution:")

    print(
        df[TARGET_COLUMN]
        .value_counts()
        .sort_index()
        .to_string()
    )

    # -----------------------------------------------------------------
    # VALIDATE GROUP
    # -----------------------------------------------------------------

    if GROUP_COLUMN not in df.columns:
        raise ValueError(
            f"Missing grouping column: "
            f"{GROUP_COLUMN}"
        )

    n_pigs = df[
        GROUP_COLUMN
    ].nunique()

    print(
        f"\nNumber of pigs: {n_pigs}"
    )

    if n_pigs < N_SPLITS:
        raise ValueError(
            "Not enough pigs for the requested "
            "number of grouped folds."
        )

    # -----------------------------------------------------------------
    # DEFINE FEATURES
    # -----------------------------------------------------------------

    print(
        "\n[3/8] Defining ML predictors..."
    )

    feature_columns = [
        column
        for column in df.columns
        if column not in METADATA_COLUMNS
    ]

    if not feature_columns:
        raise ValueError(
            "No ML feature columns found."
        )

    # -----------------------------------------------------------------
    # Validate that every feature is numeric.
    # -----------------------------------------------------------------

    non_numeric_features = [
        column
        for column in feature_columns
        if not pd.api.types.is_numeric_dtype(
            df[column]
        )
    ]

    if non_numeric_features:
        raise ValueError(
            "Non-numeric predictor columns found:\n"
            + "\n".join(
                f"  - {column}"
                for column in non_numeric_features
            )
        )

    print(
        f"Number of ML features: "
        f"{len(feature_columns)}"
    )

    # -----------------------------------------------------------------
    # Explicit leakage check
    # -----------------------------------------------------------------

    forbidden_columns = {
        TARGET_COLUMN,
        "datetime",
        "period",
        "source_dataset",
        "state",
        "unknown",
        "date_stress",
        "jour_debut_stress",
        "id_challenge",
        "ordre_challenge",
        "porc",
    }

    leakage_columns = (
        set(feature_columns)
        & forbidden_columns
    )

    if leakage_columns:
        raise ValueError(
            "Potential leakage columns found in "
            f"ML predictors: {sorted(leakage_columns)}"
        )

    print(
        "Leakage-column check: PASSED"
    )

    # -----------------------------------------------------------------
    # X / y / groups
    # -----------------------------------------------------------------

    X = df[
        feature_columns
    ].copy()

    y = df[
        TARGET_COLUMN
    ].copy()

    groups = df[
        GROUP_COLUMN
    ].copy()

    # -----------------------------------------------------------------
    # CROSS VALIDATION
    # -----------------------------------------------------------------

    print(
        "\n[4/8] Configuring grouped cross-validation..."
    )

    cv = StratifiedGroupKFold(
        n_splits=N_SPLITS,
        shuffle=True,
        random_state=RANDOM_STATE,
    )

    print(
        f"Strategy: StratifiedGroupKFold"
    )

    print(
        f"Number of folds: {N_SPLITS}"
    )

    print(
        "Grouping variable: pig_id"
    )

    # -----------------------------------------------------------------
    # OUT-OF-FOLD PREDICTIONS
    # -----------------------------------------------------------------

    print(
        "\n[5/8] Training and evaluating folds..."
    )

    oof_predictions = np.empty(
        len(df),
        dtype=object,
    )

    oof_probabilities = np.full(
        (
            len(df),
            len(VALID_TARGETS),
        ),
        np.nan,
        dtype=float,
    )

    fold_results = []

    for fold_number, (
        train_indices,
        validation_indices,
    ) in enumerate(
        cv.split(
            X,
            y,
            groups,
        ),
        start=1,
    ):

        X_train = X.iloc[
            train_indices
        ]

        X_validation = X.iloc[
            validation_indices
        ]

        y_train = y.iloc[
            train_indices
        ]

        y_validation = y.iloc[
            validation_indices
        ]

        groups_train = groups.iloc[
            train_indices
        ]

        groups_validation = groups.iloc[
            validation_indices
        ]

        train_pigs = sorted(
            groups_train.unique()
        )

        validation_pigs = sorted(
            groups_validation.unique()
        )

        overlap = set(
            train_pigs
        ) & set(
            validation_pigs
        )

        if overlap:
            raise RuntimeError(
                "Pig leakage detected in fold "
                f"{fold_number}: {sorted(overlap)}"
            )

        print(
            f"\nFold {fold_number}/{N_SPLITS}"
        )

        print(
            f"  Training rows   : "
            f"{len(train_indices):,}"
        )

        print(
            f"  Validation rows : "
            f"{len(validation_indices):,}"
        )

        print(
            f"  Training pigs   : "
            f"{train_pigs}"
        )

        print(
            f"  Validation pigs : "
            f"{validation_pigs}"
        )

        model = create_model()

        model.fit(
            X_train,
            y_train,
        )

        predictions = model.predict(
            X_validation
        )

        probabilities = model.predict_proba(
            X_validation
        )

        oof_predictions[
            validation_indices
        ] = predictions

        # Align probability columns to VALID_TARGETS.
        model_classes = list(
            model.named_steps[
                "classifier"
            ].classes_
        )

        for class_index, class_name in enumerate(
            model_classes
        ):

            target_index = VALID_TARGETS.index(
                class_name
            )

            oof_probabilities[
                validation_indices,
                target_index,
            ] = probabilities[
                :,
                class_index,
            ]

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

        precision, recall, f1, _ = (
            precision_recall_fscore_support(
                y_validation,
                predictions,
                labels=VALID_TARGETS,
                average="macro",
                zero_division=0,
            )
        )

        fold_results.append(
            {
                "fold": fold_number,
                "accuracy": accuracy,
                "balanced_accuracy": balanced_accuracy,
                "macro_precision": precision,
                "macro_recall": recall,
                "macro_f1": f1,
                "training_rows": len(
                    train_indices
                ),
                "validation_rows": len(
                    validation_indices
                ),
                "training_pigs": ",".join(
                    train_pigs
                ),
                "validation_pigs": ",".join(
                    validation_pigs
                ),
            }
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
            f"{precision:.6f}"
        )

        print(
            f"  Macro recall      : "
            f"{recall:.6f}"
        )

        print(
            f"  Macro F1          : "
            f"{f1:.6f}"
        )

    # -----------------------------------------------------------------
    # CV SUMMARY
    # -----------------------------------------------------------------

    print(
        "\n[6/8] Calculating cross-validation summary..."
    )

    fold_results_df = pd.DataFrame(
        fold_results
    )

    metric_columns = [
        "accuracy",
        "balanced_accuracy",
        "macro_precision",
        "macro_recall",
        "macro_f1",
    ]

    print(
        "\nFold results:"
    )

    print(
        fold_results_df[
            [
                "fold",
                *metric_columns,
            ]
        ].to_string(
            index=False
        )
    )

    print(
        "\nMean ± standard deviation:"
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
            ].std(ddof=1)
        )

        print(
            f"  {metric:20s}: "
            f"{mean_value:.6f} ± "
            f"{std_value:.6f}"
        )

    # -----------------------------------------------------------------
    # OUT-OF-FOLD CLASSIFICATION REPORT
    # -----------------------------------------------------------------

    print(
        "\n[7/8] Creating out-of-fold evaluation..."
    )

    classification_report_dict = (
        classification_report(
            y,
            oof_predictions,
            labels=VALID_TARGETS,
            output_dict=True,
            zero_division=0,
        )
    )

    classification_report_df = (
        pd.DataFrame(
            classification_report_dict
        ).transpose()
    )

    print(
        "\nOut-of-fold classification report:"
    )

    print(
        classification_report_df.to_string()
    )

    # -----------------------------------------------------------------
    # CONFUSION MATRIX
    # -----------------------------------------------------------------

    confusion = confusion_matrix(
        y,
        oof_predictions,
        labels=VALID_TARGETS,
    )

    confusion_df = pd.DataFrame(
        confusion,
        index=[
            f"actual_{label}"
            for label in VALID_TARGETS
        ],
        columns=[
            f"predicted_{label}"
            for label in VALID_TARGETS
        ],
    )

    print(
        "\nOut-of-fold confusion matrix:"
    )

    print(
        confusion_df.to_string()
    )

    # -----------------------------------------------------------------
    # TRAIN FINAL MODEL
    # -----------------------------------------------------------------

    print(
        "\nTraining final temporal Random Forest "
        "on all available HotPig data..."
    )

    final_model = create_model()

    final_model.fit(
        X,
        y,
    )

    # -----------------------------------------------------------------
    # FEATURE IMPORTANCE
    # -----------------------------------------------------------------

    classifier = (
        final_model.named_steps[
            "classifier"
        ]
    )

    feature_importance_df = pd.DataFrame(
        {
            "feature": feature_columns,
            "importance": classifier.feature_importances_,
        }
    ).sort_values(
        "importance",
        ascending=False,
    )

    print(
        "\nTop 25 temporal features:"
    )

    print(
        feature_importance_df
        .head(25)
        .to_string(index=False)
    )

    # -----------------------------------------------------------------
    # SAVE
    # -----------------------------------------------------------------

    print(
        "\n[8/8] Saving model and reports..."
    )

    MODEL_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    REPORT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    joblib.dump(
        final_model,
        MODEL_FILE,
    )

    fold_results_df.to_csv(
        FOLD_RESULTS_FILE,
        index=False,
    )

    classification_report_df.to_csv(
        CLASSIFICATION_REPORT_FILE
    )

    confusion_df.to_csv(
        CONFUSION_MATRIX_FILE
    )

    feature_importance_df.to_csv(
        FEATURE_IMPORTANCE_FILE,
        index=False,
    )

    print(
        f"\nModel saved:\n{MODEL_FILE}"
    )

    print(
        f"\nFold results saved:\n"
        f"{FOLD_RESULTS_FILE}"
    )

    print(
        f"\nClassification report saved:\n"
        f"{CLASSIFICATION_REPORT_FILE}"
    )

    print(
        f"\nConfusion matrix saved:\n"
        f"{CONFUSION_MATRIX_FILE}"
    )

    print(
        f"\nFeature importance saved:\n"
        f"{FEATURE_IMPORTANCE_FILE}"
    )

    print("\n" + "=" * 70)
    print(
        "Temporal HotPig model training completed."
    )
    print("=" * 70)


if __name__ == "__main__":
    main()