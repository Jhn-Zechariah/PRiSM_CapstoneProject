from pathlib import Path
import pandas as pd
import numpy as np


# ============================================================
# PROJECT PATHS
# ============================================================

PROJECT_ROOT = Path(__file__).resolve().parents[2]

DATA_DIR = PROJECT_ROOT / "data" / "processed"

HOTPIG_FILE = (
    DATA_DIR
    / "hotpig"
    / "hotpig_processed.csv"
)

INRAE_FILE = (
    DATA_DIR
    / "inrae"
    / "inrae_processed.csv"
)

BEHAVIOR_FILE = (
    DATA_DIR
    / "behavior_heat_tolerance"
    / "behavior_heat_tolerance_processed.csv"
)


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


def print_warning(message):
    print(f"\nWARNING: {message}")


def print_ok(message):
    print(f"\nOK: {message}")


# ============================================================
# GENERAL HELPERS
# ============================================================

def numeric_summary_by_target(df, target, features):
    """
    Display numerical feature statistics grouped by target.
    This is descriptive only. No modeling occurs here.
    """

    available_features = [
        feature
        for feature in features
        if feature in df.columns
    ]

    if not available_features:
        print("No requested numerical features were found.")
        return

    summary = (
        df.groupby(target, dropna=False)[available_features]
        .agg(["count", "mean", "std", "min", "max"])
    )

    print(summary.to_string())


def missingness_by_target(df, target, features):
    """
    Display missing values for candidate features by target.
    """

    available_features = [
        feature
        for feature in features
        if feature in df.columns
    ]

    if not available_features:
        return

    missing = (
        df.groupby(target, dropna=False)[available_features]
        .apply(lambda group: group.isna().sum())
    )

    print(missing.to_string())


def animal_target_coverage(
    df,
    animal_column,
    target_column
):
    """
    Determine whether each animal appears in one or multiple
    target classes.

    This is critical for grouped train/test splitting.
    """

    if (
        animal_column not in df.columns
        or target_column not in df.columns
    ):
        print(
            f"Required columns not found: "
            f"{animal_column}, {target_column}"
        )
        return

    table = pd.crosstab(
        df[animal_column],
        df[target_column],
        dropna=False
    )

    print(table.to_string())

    number_of_classes = (
        table
        .gt(0)
        .sum(axis=1)
    )

    print(
        "\nNumber of target classes represented per animal:"
    )

    print(
        number_of_classes
        .value_counts()
        .sort_index()
        .to_string()
    )

    animals_with_multiple_classes = (
        number_of_classes > 1
    ).sum()

    animals_with_one_class = (
        number_of_classes == 1
    ).sum()

    print(
        f"\nAnimals represented in multiple target classes: "
        f"{animals_with_multiple_classes}"
    )

    print(
        f"Animals represented in only one target class: "
        f"{animals_with_one_class}"
    )


def feature_target_correlation(
    df,
    target,
    features
):
    """
    For binary numeric targets, display Pearson correlations
    between numeric candidate features and the encoded target.

    This is descriptive only and is NOT used to select a model.
    """

    if target not in df.columns:
        return

    target_values = df[target].dropna().unique()

    if len(target_values) != 2:
        print(
            "Correlation audit skipped because target does "
            "not contain exactly two observed classes."
        )
        return

    available_features = [
        feature
        for feature in features
        if feature in df.columns
    ]

    numeric_features = []

    for feature in available_features:
        if pd.api.types.is_numeric_dtype(df[feature]):
            numeric_features.append(feature)

    if not numeric_features:
        print("No numeric features available.")
        return

    target_mapping = {
        value: index
        for index, value in enumerate(
            sorted(target_values, key=lambda x: str(x))
        )
    }

    numeric_target = df[target].map(target_mapping)

    correlations = {}

    for feature in numeric_features:

        valid = (
            df[feature].notna()
            & numeric_target.notna()
        )

        if valid.sum() < 2:
            continue

        correlation = (
            df.loc[valid, feature]
            .corr(numeric_target.loc[valid])
        )

        correlations[feature] = correlation

    if not correlations:
        print("No correlations could be calculated.")
        return

    correlation_series = (
        pd.Series(correlations)
        .sort_values(
            key=lambda values: values.abs(),
            ascending=False
        )
    )

    print(
        correlation_series.to_string()
    )

    print(
        "\nNOTE: High correlation does not automatically mean "
        "a feature is scientifically appropriate."
    )


# ============================================================
# HOTPIG ML TASK AUDIT
# ============================================================

def audit_hotpig_ml_task():

    print_header(
        "HOTPIG - ML TASK AND LEAKAGE AUDIT"
    )

    if not HOTPIG_FILE.exists():
        raise FileNotFoundError(
            f"HotPig processed file not found:\n{HOTPIG_FILE}"
        )

    print(f"\nReading:")
    print(HOTPIG_FILE)

    df = pd.read_csv(HOTPIG_FILE)

    print(
        f"\nRows: {len(df):,}"
    )

    # --------------------------------------------------------
    # Candidate target
    # --------------------------------------------------------

    target = "conditions"

    print_subheader(
        "1. Candidate Target: conditions"
    )

    print(
        df[target]
        .value_counts(dropna=False)
        .to_string()
    )

    print(
        """
Interpretation:

The source experiment explicitly records:
    TN
    TU
    HS
    TD

These are experimental conditions from the dataset.

They are NOT being converted into:
    GOOD
    NEEDS_ATTENTION
    HIGH_RISK
"""
    )

    # --------------------------------------------------------
    # Candidate features
    # --------------------------------------------------------

    candidate_features = [
        "feed",
        "unknown",
        "standing",
        "seating",
        "lying",
        "eating",
        "drinking",
        "cuddling",
        "curious",
        "idle",
        "drink",
        "eat",
        "mate",
        "state",
    ]

    print_subheader(
        "2. Candidate Features"
    )

    for feature in candidate_features:

        if feature in df.columns:

            print(
                f"{feature:<15} "
                f"dtype={str(df[feature].dtype):<10} "
                f"unique={df[feature].nunique(dropna=False):,} "
                f"missing={df[feature].isna().sum():,}"
            )

        else:

            print(
                f"{feature:<15} NOT FOUND"
            )

    # --------------------------------------------------------
    # Explicit leakage candidates
    # --------------------------------------------------------

    print_subheader(
        "3. Features That Must NOT Be Used Directly"
    )

    leakage_candidates = [
        "conditions",
        "datetime",
        "period",
        "pig_id",
        "source_dataset",
    ]

    for column in leakage_candidates:

        if column in df.columns:

            print(
                f"EXCLUDE: {column}"
            )

    print(
        """
Reason:

conditions is the target.

datetime can reveal the experimental schedule.

period may encode the experimental schedule.

pig_id identifies the individual animal and can cause
animal-identity leakage.

source_dataset contains no biological predictive information.
"""
    )

    # --------------------------------------------------------
    # Target by pig
    # --------------------------------------------------------

    print_subheader(
        "4. Target Coverage by Pig"
    )

    animal_target_coverage(
        df,
        "pig_id",
        target
    )

    # --------------------------------------------------------
    # Feature statistics
    # --------------------------------------------------------

    print_subheader(
        "5. Candidate Feature Statistics by Condition"
    )

    numeric_features = [
        feature
        for feature in candidate_features
        if feature in df.columns
        and pd.api.types.is_numeric_dtype(df[feature])
    ]

    numeric_summary_by_target(
        df,
        target,
        numeric_features
    )

    # --------------------------------------------------------
    # Missingness
    # --------------------------------------------------------

    print_subheader(
        "6. Missing Values by Condition"
    )

    missingness_by_target(
        df,
        target,
        candidate_features
    )

    # --------------------------------------------------------
    # Feature-target correlation
    # --------------------------------------------------------

    print_subheader(
        "7. Descriptive Feature/Target Correlations"
    )

    print(
        "HotPig has four target classes, so binary correlation "
        "analysis is not used here."
    )

    # --------------------------------------------------------
    # State inspection
    # --------------------------------------------------------

    print_subheader(
        "8. 'state' Feature Inspection"
    )

    if "state" in df.columns:

        print(
            df["state"]
            .value_counts(dropna=False)
            .head(50)
            .to_string()
        )

        print(
            """
IMPORTANT:

Before using 'state' as a feature, we need to establish
exactly what this field represents in the original HotPig
experiment.

It must not be used merely because it correlates with
conditions.
"""
        )

    # --------------------------------------------------------
    # Unknown feature
    # --------------------------------------------------------

    print_subheader(
        "9. 'unknown' Feature Inspection"
    )

    if "unknown" in df.columns:

        print(
            df["unknown"]
            .describe()
            .to_string()
        )

        print(
            """
The 'unknown' variable should not automatically be used.

Its scientific meaning needs to be confirmed from the
original HotPig documentation before including it in
the ML feature set.
"""
        )

    # --------------------------------------------------------
    # Recommendation
    # --------------------------------------------------------

    print_subheader(
        "10. HotPig Preliminary Assessment"
    )

    print(
        """
Potential ML formulation:

    behavioral measurements
            ↓
       ML classifier
            ↓
    experimental condition

Potential target:
    conditions

Potential candidate features:
    behavioral measurements

Must exclude:
    conditions
    datetime
    period
    pig_id
    source_dataset

Important unresolved issue:

The HotPig experiment follows a fixed sequence:

    TN → TU → HS → TD

Therefore, we must verify that a model using only
behavioral measurements is learning behavioral differences
rather than reconstructing the experimental schedule.

No model should be trained until this is addressed.
"""
    )


# ============================================================
# INRAE ML TASK AUDIT
# ============================================================

def audit_inrae_ml_task():

    print_header(
        "INRAE - ML TASK AND LEAKAGE AUDIT"
    )

    if not INRAE_FILE.exists():
        raise FileNotFoundError(
            f"INRAE processed file not found:\n{INRAE_FILE}"
        )

    print(f"\nReading:")
    print(INRAE_FILE)

    # Low-memory read to reduce memory pressure.
    df = pd.read_csv(
        INRAE_FILE,
        low_memory=False
    )

    print(
        f"\nRows: {len(df):,}"
    )

    target = "periode"

    # --------------------------------------------------------
    # Target
    # --------------------------------------------------------

    print_subheader(
        "1. Candidate Target: periode"
    )

    print(
        df[target]
        .value_counts(dropna=False)
        .to_string()
    )

    # --------------------------------------------------------
    # Candidate features
    # --------------------------------------------------------

    candidate_features = [
        "T_IM",
        "T",
        "age",
        "ADFI",
        "stage",
        "temps_relatif_jour",
    ]

    print_subheader(
        "2. Candidate Features"
    )

    for feature in candidate_features:

        if feature in df.columns:

            print(
                f"{feature:<20} "
                f"dtype={str(df[feature].dtype):<12} "
                f"unique={df[feature].nunique(dropna=False):,} "
                f"missing={df[feature].isna().sum():,}"
            )

        else:

            print(
                f"{feature:<20} NOT FOUND"
            )

    # --------------------------------------------------------
    # Leakage candidates
    # --------------------------------------------------------

    print_subheader(
        "3. Features That Require Special Attention"
    )

    leakage_candidates = [
        "periode",
        "datetime",
        "date_stress",
        "jour_debut_stress",
        "id_challenge",
        "ordre_challenge",
        "porc",
        "source_dataset",
    ]

    for column in leakage_candidates:

        if column in df.columns:

            print(
                f"CAUTION / EXCLUDE: {column}"
            )

    print(
        """
Important:

T is environmental temperature.

Because the experimental periods are associated with
different environmental temperatures, T may make
prediction of 'periode' extremely easy.

That does not automatically make T invalid, but we must
test whether the task becomes trivial.

porc is the pig identifier and should not be used as a
normal predictive feature.

datetime and challenge-related identifiers may encode
experimental schedule or study structure.
"""
    )

    # --------------------------------------------------------
    # Target by pig
    # --------------------------------------------------------

    print_subheader(
        "4. Target Coverage by Pig"
    )

    animal_target_coverage(
        df,
        "porc",
        target
    )

    # --------------------------------------------------------
    # Feature statistics by target
    # --------------------------------------------------------

    print_subheader(
        "5. Candidate Feature Statistics by Experimental Period"
    )

    numeric_features = [
        feature
        for feature in candidate_features
        if feature in df.columns
        and pd.api.types.is_numeric_dtype(df[feature])
    ]

    numeric_summary_by_target(
        df,
        target,
        numeric_features
    )

    # --------------------------------------------------------
    # Missingness
    # --------------------------------------------------------

    print_subheader(
        "6. Missing Values by Experimental Period"
    )

    missingness_by_target(
        df,
        target,
        candidate_features
    )

    # --------------------------------------------------------
    # Binary correlations
    # --------------------------------------------------------

    print_subheader(
        "7. Feature/Target Correlation Check"
    )

    print(
        "The target contains three classes, so binary "
        "correlation analysis is not used."
    )

    # --------------------------------------------------------
    # Environmental temperature
    # --------------------------------------------------------

    print_subheader(
        "8. Environmental Temperature Analysis"
    )

    if "T" in df.columns:

        print(
            df.groupby("periode", dropna=False)["T"]
            .agg(
                [
                    "count",
                    "nunique",
                    "mean",
                    "std",
                    "min",
                    "max",
                ]
            )
            .to_string()
        )

        print(
            """
Interpretation:

If environmental temperature almost completely determines
the experimental period, then using T alone could produce
very high accuracy without demonstrating meaningful
physiological prediction.

We therefore need to distinguish:

A) environmental-condition classification

from:

B) physiological-response prediction.
"""
        )

    # --------------------------------------------------------
    # Core temperature
    # --------------------------------------------------------

    print_subheader(
        "9. Core Temperature Analysis"
    )

    if "T_IM" in df.columns:

        print(
            df.groupby("periode", dropna=False)["T_IM"]
            .agg(
                [
                    "count",
                    "mean",
                    "std",
                    "min",
                    "max",
                ]
            )
            .to_string()
        )

        print(
            """
T_IM appears particularly important because it is a
physiological measurement rather than simply the
experimental environmental temperature.

However, whether T_IM should be an input or target depends
on the final research question.
"""
        )

    # --------------------------------------------------------
    # Recommendation
    # --------------------------------------------------------

    print_subheader(
        "10. INRAE Preliminary Assessment"
    )

    print(
        """
INRAE provides a strong experimental structure:

    195 pigs
    3 experimental periods
    most pigs represented in all 3 periods

Potential ML target:

    periode

However, the initial feature set must be carefully designed.

In particular:

    T
    datetime
    challenge identifiers
    experimental ordering

may reveal the experimental condition directly.

A scientifically stronger future formulation may involve
predicting physiological response from environmental and
behavioral information rather than simply predicting the
experimental label.
"""
    )


# ============================================================
# BEHAVIOR-HEATTOLERANCE ML TASK AUDIT
# ============================================================

def audit_behavior_ml_task():

    print_header(
        "BEHAVIOR-HEATTOLERANCE - ML TASK AND LEAKAGE AUDIT"
    )

    if not BEHAVIOR_FILE.exists():
        raise FileNotFoundError(
            "Behavior-HeatTolerance processed file not found:\n"
            f"{BEHAVIOR_FILE}"
        )

    print(f"\nReading:")
    print(BEHAVIOR_FILE)

    df = pd.read_csv(BEHAVIOR_FILE)

    print(
        f"\nRows: {len(df):,}"
    )

    target = "condition"

    # --------------------------------------------------------
    # Target
    # --------------------------------------------------------

    print_subheader(
        "1. Candidate Target: condition"
    )

    print(
        df[target]
        .value_counts(dropna=False)
        .to_string()
    )

    # --------------------------------------------------------
    # Candidate features
    # --------------------------------------------------------

    candidate_features = [
        "muscle_temp",
        "ambient_temp",
        "posture",
        "adg",
        "feed_efficiency",
    ]

    print_subheader(
        "2. Candidate Features"
    )

    for feature in candidate_features:

        if feature in df.columns:

            print(
                f"{feature:<20} "
                f"dtype={str(df[feature].dtype):<12} "
                f"unique={df[feature].nunique(dropna=False):,} "
                f"missing={df[feature].isna().sum():,}"
            )

        else:

            print(
                f"{feature:<20} NOT FOUND"
            )

    # --------------------------------------------------------
    # Animal coverage
    # --------------------------------------------------------

    print_subheader(
        "3. Target Coverage by Animal"
    )

    animal_target_coverage(
        df,
        "anim",
        target
    )

    # --------------------------------------------------------
    # Feature statistics
    # --------------------------------------------------------

    print_subheader(
        "4. Feature Statistics by Condition"
    )

    numeric_features = [
        "muscle_temp",
        "ambient_temp",
        "adg",
        "feed_efficiency",
    ]

    numeric_summary_by_target(
        df,
        target,
        numeric_features
    )

    # --------------------------------------------------------
    # Missingness
    # --------------------------------------------------------

    print_subheader(
        "5. Missing Values by Condition"
    )

    missingness_by_target(
        df,
        target,
        candidate_features
    )

    # --------------------------------------------------------
    # Correlation
    # --------------------------------------------------------

    print_subheader(
        "6. Binary Feature/Target Correlation"
    )

    feature_target_correlation(
        df,
        target,
        numeric_features
    )

    # --------------------------------------------------------
    # Posture
    # --------------------------------------------------------

    print_subheader(
        "7. Posture Distribution by Condition"
    )

    if (
        "posture" in df.columns
        and "condition" in df.columns
    ):

        posture_table = pd.crosstab(
            df["condition"],
            df["posture"],
            normalize="index"
        ) * 100

        print(
            posture_table.round(2).to_string()
        )

    # --------------------------------------------------------
    # Critical interpretation
    # --------------------------------------------------------

    print_subheader(
        "8. Behavior-HeatTolerance Preliminary Assessment"
    )

    print(
        """
Critical finding:

Each animal appears in only one experimental condition.

Therefore:

    animal identity
            ↕
    experimental condition

are strongly confounded.

This dataset should NOT automatically become the primary
generalization dataset for a condition classifier.

It may still be useful for:

    - exploratory analysis
    - supporting evidence
    - feature analysis
    - later research questions

but its limitations must be explicitly documented.
"""
    )


# ============================================================
# CROSS-DATASET SUMMARY
# ============================================================

def print_final_summary():

    print_header(
        "CROSS-DATASET ML TASK SUMMARY"
    )

    print(
        """
CURRENT DATASET ASSESSMENT
==========================

1. HOTPIG
   ----------------------------------------
   Strength:
       Same pigs experience multiple thermal conditions.

   Candidate target:
       conditions

   Candidate predictors:
       behavioral measurements

   Main danger:
       fixed experimental schedule can create
       temporal leakage.

   Status:
       STRONG CANDIDATE, requires leakage validation.


2. INRAE
   ----------------------------------------
   Strength:
       195 pigs and most pigs experience all
       three experimental periods.

   Candidate target:
       periode

   Candidate predictors:
       physiological/environmental variables

   Main danger:
       environmental temperature and experimental
       schedule may make the target trivial.

   Status:
       STRONG CANDIDATE, requires task refinement.


3. BEHAVIOR-HEATTOLERANCE
   ----------------------------------------
   Strength:
       genuine TN/HS experimental observations.

   Limitation:
       every animal belongs to only one condition.

   Main danger:
       animal identity is confounded with condition.

   Status:
       SUPPORTING DATASET, not preferred as the
       first primary generalization experiment.


IMPORTANT
=========

We still have NOT trained a model.

We still have NOT created PRISM labels.

We still have NOT merged datasets.

We still have NOT created synthetic data.

The next decision should be based on these audits.
"""
    )


# ============================================================
# MAIN
# ============================================================

def main():

    print("\n")
    print("#" * 80)
    print("# PRISM ML - ML TASK AUDIT")
    print("#")
    print("# Purpose:")
    print("#   Determine whether candidate public-data ML tasks")
    print("#   are scientifically defensible before training.")
    print("#")
    print("# This script DOES NOT:")
    print("#   - train models")
    print("#   - create labels")
    print("#   - create synthetic data")
    print("#   - modify datasets")
    print("#   - merge datasets")
    print("#" * 80)

    audit_hotpig_ml_task()

    audit_inrae_ml_task()

    audit_behavior_ml_task()

    print_final_summary()

    print_header(
        "ML TASK AUDIT COMPLETE"
    )

    print(
        """
No datasets were modified.
No labels were created.
No synthetic observations were created.
No datasets were merged.
No ML model was trained.

Review this output before proceeding to feature engineering
and model training.
"""
    )


if __name__ == "__main__":
    main()