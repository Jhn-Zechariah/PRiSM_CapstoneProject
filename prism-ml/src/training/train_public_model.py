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
    f1_score,
    precision_score,
    recall_score,
)
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.pipeline import Pipeline


# ============================================================
# PROJECT PATHS
# ============================================================

PROJECT_ROOT = Path(__file__).resolve().parents[2]

INPUT_FILE = (
    PROJECT_ROOT
    / "data"
    / "processed"
    / "hotpig"
    / "hotpig_ml_features_5min.csv"
)

MODEL_DIR = (
    PROJECT_ROOT
    / "models"
)

REPORT_DIR = (
    PROJECT_ROOT
    / "reports"
)

MODEL_FILE = (
    MODEL_DIR
    / "hotpig_public_random_forest.joblib"
)

FEATURE_IMPORTANCE_FILE = (
    REPORT_DIR
    / "hotpig_feature_importance.csv"
)

FOLD_RESULTS_FILE = (
    REPORT_DIR
    / "hotpig_grouped_cv_results.csv"
)

CONFUSION_MATRIX_FILE = (
    REPORT_DIR
    / "hotpig_confusion_matrix.csv"
)

CLASSIFICATION_REPORT_FILE = (
    REPORT_DIR
    / "hotpig_classification_report.csv"
)


# ============================================================
# CONFIGURATION
# ============================================================

TARGET_COLUMN = "conditions"
GROUP_COLUMN = "pig_id"
TRACEABILITY_COLUMN = "window_start"

RANDOM_STATE = 42

N_SPLITS = 5

N_ESTIMATORS = 400

N_JOBS = -1


# ============================================================
# DISPLAY HELPERS
# ============================================================

def print_header(title):
    print("\n" + "=" * 80)
    print(title)
    print("=" * 80)


def print_subheader(title):
    print("\n" + "-" * 80)
    print(title)
    print("-" * 80)


# ============================================================
# LOAD DATA
# ============================================================

def load_dataset():

    print_header("1. LOADING ML-READY HOTPIG DATASET")

    if not INPUT_FILE.exists():
        raise FileNotFoundError(
            f"ML-ready HotPig dataset was not found:\n{INPUT_FILE}\n\n"
            "Run feature_engineering.py first."
        )

    print(f"Input file:\n{INPUT_FILE}")

    df = pd.read_csv(
        INPUT_FILE,
        low_memory=False,
    )

    print(f"\nRows: {len(df):,}")
    print(f"Columns: {len(df.columns)}")

    return df


# ============================================================
# VALIDATE DATASET
# ============================================================

def validate_dataset(df):

    print_header("2. VALIDATING TRAINING DATA")

    required_columns = [
        TARGET_COLUMN,
        GROUP_COLUMN,
        TRACEABILITY_COLUMN,
    ]

    missing = [
        column
        for column in required_columns
        if column not in df.columns
    ]

    if missing:
        raise ValueError(
            "Required columns are missing:\n"
            + "\n".join(missing)
        )

    # --------------------------------------------------------
    # Target validation
    # --------------------------------------------------------

    if df[TARGET_COLUMN].isna().any():

        raise ValueError(
            "The target contains missing values."
        )

    classes = sorted(
        df[TARGET_COLUMN]
        .unique()
    )

    expected_classes = {
        "TN",
        "TU",
        "HS",
        "TD",
    }

    if set(classes) != expected_classes:

        raise ValueError(
            "Unexpected target classes.\n"
            f"Expected: {sorted(expected_classes)}\n"
            f"Found:    {classes}"
        )

    print(
        f"Target classes: {classes}"
    )

    # --------------------------------------------------------
    # Group validation
    # --------------------------------------------------------

    if df[GROUP_COLUMN].isna().any():

        raise ValueError(
            "pig_id contains missing values."
        )

    pigs = sorted(
        df[GROUP_COLUMN]
        .unique()
    )

    print(
        f"Number of pigs: {len(pigs)}"
    )

    print(
        f"Pigs: {pigs}"
    )

    # --------------------------------------------------------
    # Verify every pig has all classes
    # --------------------------------------------------------

    class_by_pig = pd.crosstab(
        df[GROUP_COLUMN],
        df[TARGET_COLUMN],
    )

    missing_classes = (
        class_by_pig == 0
    ).any(axis=1)

    if missing_classes.any():

        print(
            "\nWARNING:"
        )

        print(
            class_by_pig[
                missing_classes
            ].to_string()
        )

    else:

        print(
            "\nEvery pig contains all four experimental conditions."
        )


# ============================================================
# DEFINE FEATURES
# ============================================================

def define_features(df):

    print_header("3. DEFINING ML FEATURES")

    excluded_columns = {
        TARGET_COLUMN,
        GROUP_COLUMN,
        TRACEABILITY_COLUMN,
    }

    feature_columns = [
        column
        for column in df.columns
        if column not in excluded_columns
    ]

    if not feature_columns:

        raise ValueError(
            "No ML feature columns were found."
        )

    # --------------------------------------------------------
    # Explicit leakage check
    # --------------------------------------------------------

    forbidden_columns = {
        "datetime",
        "period",
        "conditions",
        "pig_id",
        "source_dataset",
        "state",
        "unknown",
    }

    forbidden_found = (
        forbidden_columns
        .intersection(feature_columns)
    )

    if forbidden_found:

        raise ValueError(
            "Potential leakage/non-feature columns found:\n"
            + "\n".join(
                sorted(forbidden_found)
            )
        )

    # --------------------------------------------------------
    # Verify numeric features
    # --------------------------------------------------------

    non_numeric = []

    for column in feature_columns:

        if not pd.api.types.is_numeric_dtype(
            df[column]
        ):
            non_numeric.append(column)

    if non_numeric:

        raise ValueError(
            "Non-numeric ML features found:\n"
            + "\n".join(non_numeric)
        )

    print(
        f"Number of ML features: "
        f"{len(feature_columns)}"
    )

    print("\nFeatures:")

    for index, column in enumerate(
        feature_columns,
        start=1,
    ):
        print(
            f"{index:>3}. {column}"
        )

    print(
        """
Excluded from X:

    pig_id
        Used only to keep observations from the same pig
        together during grouped cross-validation.

    window_start
        Retained only for traceability.

    conditions
        Genuine experimental target.

No experimental schedule or animal identity is supplied
to the classifier.
"""
    )

    return feature_columns


# ============================================================
# PREPARE X / Y / GROUPS
# ============================================================

def prepare_training_data(
    df,
    feature_columns,
):

    print_header("4. PREPARING X, Y, AND GROUPS")

    X = df[
        feature_columns
    ].copy()

    y = df[
        TARGET_COLUMN
    ].copy()

    groups = df[
        GROUP_COLUMN
    ].copy()

    print(
        f"X shape: {X.shape}"
    )

    print(
        f"y shape: {y.shape}"
    )

    print(
        f"Groups: {groups.nunique()}"
    )

    print("\nTarget distribution:")

    print(
        y.value_counts()
        .sort_index()
        .to_string()
    )

    missing_features = (
        X.isna()
        .sum()
    )

    missing_features = (
        missing_features[
            missing_features > 0
        ]
        .sort_values(
            ascending=False
        )
    )

    if not missing_features.empty:

        print(
            "\nMissing feature values:"
        )

        print(
            missing_features
            .to_string()
        )

        print(
            """
These values will be imputed inside the sklearn pipeline.

The imputer is fitted separately within every training fold.
Therefore validation data cannot influence the imputation
statistics.
"""
        )

    else:

        print(
            "\nNo missing feature values detected."
        )

    return X, y, groups


# ============================================================
# CREATE MODEL PIPELINE
# ============================================================

def create_model():

    print_header("5. CREATING ML PIPELINE")

    print(
        """
Model:

    SimpleImputer
        +
    RandomForestClassifier

The imputer is part of the sklearn Pipeline so that it is
fitted only on the training portion of each fold.

The classifier learns the relationship between behavioral
features and the genuine HotPig experimental condition.

No deterministic rules are used.
"""
    )

    model = Pipeline(
        steps=[
            (
                "imputer",
                SimpleImputer(
                    strategy="median",
                ),
            ),
            (
                "classifier",
                RandomForestClassifier(
                    n_estimators=N_ESTIMATORS,
                    class_weight="balanced",
                    random_state=RANDOM_STATE,
                    n_jobs=N_JOBS,
                ),
            ),
        ]
    )

    return model


# ============================================================
# GROUPED CROSS-VALIDATION
# ============================================================

def run_grouped_cross_validation(
    X,
    y,
    groups,
    feature_columns,
):

    print_header(
        "6. STRATIFIED GROUPED CROSS-VALIDATION"
    )

    print(
        f"Number of folds: {N_SPLITS}"
    )

    print(
        f"Random state: {RANDOM_STATE}"
    )

    print(
        """
IMPORTANT:

The grouping variable is pig_id.

Therefore all windows belonging to a pig remain together
inside either the training or validation portion of a fold.

This prevents the model from being evaluated on windows from
pigs it has already seen during training.
"""
    )

    cv = StratifiedGroupKFold(
        n_splits=N_SPLITS,
        shuffle=True,
        random_state=RANDOM_STATE,
    )

    fold_results = []

    all_true = []
    all_pred = []

    classes = [
        "HS",
        "TD",
        "TN",
        "TU",
    ]

    for fold_number, (
        train_indices,
        validation_indices,
    ) in enumerate(
        cv.split(
            X,
            y,
            groups=groups,
        ),
        start=1,
    ):

        print_subheader(
            f"FOLD {fold_number}"
        )

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

        overlap = (
            set(train_pigs)
            .intersection(
                validation_pigs
            )
        )

        if overlap:

            raise RuntimeError(
                "DATA LEAKAGE DETECTED: "
                "a pig appears in both training and validation."
            )

        print(
            f"Training pigs: "
            f"{train_pigs}"
        )

        print(
            f"Validation pigs: "
            f"{validation_pigs}"
        )

        print(
            f"Training rows: "
            f"{len(train_indices):,}"
        )

        print(
            f"Validation rows: "
            f"{len(validation_indices):,}"
        )

        # ----------------------------------------------------
        # Create fresh pipeline for this fold
        # ----------------------------------------------------

        model = create_model()

        # ----------------------------------------------------
        # Train
        # ----------------------------------------------------

        model.fit(
            X_train,
            y_train,
        )

        # ----------------------------------------------------
        # Predict
        # ----------------------------------------------------

        predictions = model.predict(
            X_validation
        )

        # ----------------------------------------------------
        # Metrics
        # ----------------------------------------------------

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

        macro_f1 = f1_score(
            y_validation,
            predictions,
            average="macro",
            zero_division=0,
        )

        macro_precision = precision_score(
            y_validation,
            predictions,
            average="macro",
            zero_division=0,
        )

        macro_recall = recall_score(
            y_validation,
            predictions,
            average="macro",
            zero_division=0,
        )

        print(
            f"\nAccuracy:           {accuracy:.4f}"
        )

        print(
            f"Balanced accuracy:  {balanced_accuracy:.4f}"
        )

        print(
            f"Macro precision:    {macro_precision:.4f}"
        )

        print(
            f"Macro recall:       {macro_recall:.4f}"
        )

        print(
            f"Macro F1:           {macro_f1:.4f}"
        )

        print(
            "\nClassification report:"
        )

        print(
            classification_report(
                y_validation,
                predictions,
                labels=classes,
                zero_division=0,
            )
        )

        # ----------------------------------------------------
        # Save fold metrics
        # ----------------------------------------------------

        fold_results.append(
            {
                "fold": fold_number,
                "train_pigs": ",".join(
                    train_pigs
                ),
                "validation_pigs": ",".join(
                    validation_pigs
                ),
                "train_rows": len(
                    train_indices
                ),
                "validation_rows": len(
                    validation_indices
                ),
                "accuracy": accuracy,
                "balanced_accuracy": balanced_accuracy,
                "macro_precision": macro_precision,
                "macro_recall": macro_recall,
                "macro_f1": macro_f1,
            }
        )

        all_true.extend(
            y_validation.tolist()
        )

        all_pred.extend(
            predictions.tolist()
        )

    results_df = pd.DataFrame(
        fold_results
    )

    return (
        results_df,
        np.array(all_true),
        np.array(all_pred),
    )


# ============================================================
# REPORT CROSS-VALIDATION RESULTS
# ============================================================

def report_cross_validation_results(
    results_df,
):

    print_header(
        "7. CROSS-VALIDATION SUMMARY"
    )

    metric_columns = [
        "accuracy",
        "balanced_accuracy",
        "macro_precision",
        "macro_recall",
        "macro_f1",
    ]

    print(
        results_df[
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

        mean = results_df[
            metric
        ].mean()

        std = results_df[
            metric
        ].std()

        print(
            f"{metric:20s}: "
            f"{mean:.4f} ± {std:.4f}"
        )

    print(
        """
The cross-validation metrics above are the primary evidence
for how well this behavioral model generalizes to unseen pigs.

Do NOT interpret these numbers as evidence that the model can
already produce PRISM's future farm-level risk classes.
The current target is only the genuine HotPig experimental
condition.
"""
    )


# ============================================================
# OUT-OF-FOLD CLASSIFICATION REPORT
# ============================================================

def create_oof_reports(
    y_true,
    y_pred,
):

    print_header(
        "8. OUT-OF-FOLD EVALUATION REPORT"
    )

    classes = [
        "HS",
        "TD",
        "TN",
        "TU",
    ]

    report = classification_report(
        y_true,
        y_pred,
        labels=classes,
        output_dict=True,
        zero_division=0,
    )

    report_df = (
        pd.DataFrame(
            report
        )
        .T
    )

    print(
        report_df.to_string()
    )

    matrix = confusion_matrix(
        y_true,
        y_pred,
        labels=classes,
    )

    confusion_df = pd.DataFrame(
        matrix,
        index=[
            f"actual_{label}"
            for label in classes
        ],
        columns=[
            f"predicted_{label}"
            for label in classes
        ],
    )

    print(
        "\nConfusion matrix:"
    )

    print(
        confusion_df.to_string()
    )

    return (
        report_df,
        confusion_df,
    )


# ============================================================
# TRAIN FINAL MODEL ON ALL PIGS
# ============================================================

def train_final_model(
    X,
    y,
):

    print_header(
        "9. TRAINING FINAL PUBLIC-DATA MODEL"
    )

    print(
        """
After grouped cross-validation has estimated generalization
performance, a final model is fitted using all available
HotPig training data.

This final model is NOT used to claim unbiased performance.
The cross-validation results above are the evaluation.

The final model is simply the model artifact that can later
be used as the starting public-data model.
"""
    )

    final_model = create_model()

    final_model.fit(
        X,
        y,
    )

    print(
        "Final model training complete."
    )

    return final_model


# ============================================================
# FEATURE IMPORTANCE
# ============================================================

def extract_feature_importance(
    model,
    feature_columns,
):

    print_header(
        "10. EXTRACTING FEATURE IMPORTANCE"
    )

    classifier = model.named_steps[
        "classifier"
    ]

    importance = (
        classifier.feature_importances_
    )

    importance_df = pd.DataFrame(
        {
            "feature": feature_columns,
            "importance": importance,
        }
    )

    importance_df = (
        importance_df
        .sort_values(
            "importance",
            ascending=False,
        )
        .reset_index(
            drop=True
        )
    )

    print(
        importance_df.head(
            20
        ).to_string(
            index=False
        )
    )

    return importance_df


# ============================================================
# SAVE REPORTS
# ============================================================

def save_reports(
    results_df,
    report_df,
    confusion_df,
    importance_df,
):

    print_header(
        "11. SAVING REPORTS"
    )

    REPORT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    results_df.to_csv(
        FOLD_RESULTS_FILE,
        index=False,
    )

    report_df.to_csv(
        CLASSIFICATION_REPORT_FILE
    )

    confusion_df.to_csv(
        CONFUSION_MATRIX_FILE
    )

    importance_df.to_csv(
        FEATURE_IMPORTANCE_FILE,
        index=False,
    )

    print(
        f"Fold results:\n{FOLD_RESULTS_FILE}"
    )

    print(
        f"\nClassification report:\n"
        f"{CLASSIFICATION_REPORT_FILE}"
    )

    print(
        f"\nConfusion matrix:\n"
        f"{CONFUSION_MATRIX_FILE}"
    )

    print(
        f"\nFeature importance:\n"
        f"{FEATURE_IMPORTANCE_FILE}"
    )


# ============================================================
# SAVE MODEL
# ============================================================

def save_model(model):

    print_header(
        "12. SAVING FINAL MODEL"
    )

    MODEL_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    joblib.dump(
        model,
        MODEL_FILE,
    )

    print(
        f"Model saved:\n{MODEL_FILE}"
    )


# ============================================================
# MAIN
# ============================================================

def main():

    print("\n")
    print("#" * 80)
    print("# PRISM ML - PUBLIC HOTPIG MODEL TRAINING")
    print("#")
    print("# Genuine experimental data only")
    print("# Grouped evaluation by pig")
    print("# No synthetic observations")
    print("# No synthetic labels")
    print("# No deterministic prediction rules")
    print("#" * 80)

    # --------------------------------------------------------
    # Load
    # --------------------------------------------------------

    df = load_dataset()

    # --------------------------------------------------------
    # Validate
    # --------------------------------------------------------

    validate_dataset(
        df
    )

    # --------------------------------------------------------
    # Features
    # --------------------------------------------------------

    feature_columns = define_features(
        df
    )

    # --------------------------------------------------------
    # X / y / groups
    # --------------------------------------------------------

    X, y, groups = prepare_training_data(
        df,
        feature_columns,
    )

    # --------------------------------------------------------
    # Grouped CV
    # --------------------------------------------------------

    (
        results_df,
        y_true,
        y_pred,
    ) = run_grouped_cross_validation(
        X,
        y,
        groups,
        feature_columns,
    )

    # --------------------------------------------------------
    # Summary
    # --------------------------------------------------------

    report_cross_validation_results(
        results_df
    )

    # --------------------------------------------------------
    # OOF report
    # --------------------------------------------------------

    (
        report_df,
        confusion_df,
    ) = create_oof_reports(
        y_true,
        y_pred,
    )

    # --------------------------------------------------------
    # Final model
    # --------------------------------------------------------

    final_model = train_final_model(
        X,
        y,
    )

    # --------------------------------------------------------
    # Feature importance
    # --------------------------------------------------------

    importance_df = extract_feature_importance(
        final_model,
        feature_columns,
    )

    # --------------------------------------------------------
    # Save reports
    # --------------------------------------------------------

    save_reports(
        results_df,
        report_df,
        confusion_df,
        importance_df,
    )

    # --------------------------------------------------------
    # Save model
    # --------------------------------------------------------

    save_model(
        final_model
    )

    # --------------------------------------------------------
    # Complete
    # --------------------------------------------------------

    print_header(
        "PUBLIC MODEL TRAINING COMPLETE"
    )

    print(
        """
The genuine HotPig Random Forest baseline has been trained.

Important:

The model predicts:

    TN / TU / HS / TD

These are the experimental labels supplied by the HotPig
dataset.

They are NOT:

    GOOD / NEEDS_ATTENTION / HIGH_RISK

No mapping between those label systems has been created.

The saved model is therefore a public-data experimental
condition classifier, not yet the final PRISM farm-risk model.
"""
    )


if __name__ == "__main__":
    main()