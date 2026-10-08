from pathlib import Path

import numpy as np
import pandas as pd


# ============================================================
# PROJECT PATHS
# ============================================================

PROJECT_ROOT = Path(__file__).resolve().parents[2]

INPUT_FILE = (
    PROJECT_ROOT
    / "data"
    / "processed"
    / "hotpig"
    / "hotpig_processed.csv"
)

OUTPUT_DIR = (
    PROJECT_ROOT
    / "data"
    / "processed"
    / "hotpig"
)

OUTPUT_FILE = (
    OUTPUT_DIR
    / "hotpig_ml_features_5min.csv"
)


# ============================================================
# CONFIGURATION
# ============================================================

WINDOW_MINUTES = 5

TARGET_COLUMN = "conditions"
GROUP_COLUMN = "pig_id"
TIME_COLUMN = "datetime"

# These are the behavioral measurements we are currently
# willing to consider as candidate predictors.
#
# "unknown" is excluded because its meaning has not yet
# been established.
#
# "state" is excluded because its meaning and derivation
# require further verification.
BEHAVIOR_FEATURES = [
    "feed",
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
]


# ============================================================
# HELPERS
# ============================================================

def print_header(title):
    print("\n" + "=" * 80)
    print(title)
    print("=" * 80)


def print_subheader(title):
    print("\n" + "-" * 80)
    print(title)
    print("-" * 80)


def require_columns(df, required_columns):
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


# ============================================================
# LOAD DATA
# ============================================================

def load_data():
    print_header("1. LOADING HOTPIG DATA")

    if not INPUT_FILE.exists():
        raise FileNotFoundError(
            f"Processed HotPig file was not found:\n{INPUT_FILE}"
        )

    print(f"Input file:\n{INPUT_FILE}")

    df = pd.read_csv(
        INPUT_FILE,
        low_memory=False
    )

    print(f"\nRows loaded: {len(df):,}")
    print(f"Columns loaded: {len(df.columns)}")

    return df


# ============================================================
# VALIDATE SOURCE STRUCTURE
# ============================================================

def validate_source(df):
    print_header("2. VALIDATING SOURCE STRUCTURE")

    required_columns = [
        TIME_COLUMN,
        GROUP_COLUMN,
        TARGET_COLUMN,
        *BEHAVIOR_FEATURES,
    ]

    require_columns(
        df,
        required_columns
    )

    print("Required columns are present.")

    print("\nBehavior features:")
    for column in BEHAVIOR_FEATURES:
        print(f"  - {column}")

    print(f"\nTarget: {TARGET_COLUMN}")
    print(f"Group:  {GROUP_COLUMN}")
    print(f"Time:   {TIME_COLUMN}")


# ============================================================
# CLEAN SOURCE DATA
# ============================================================

def clean_source(df):
    print_header("3. CLEANING SOURCE DATA")

    df = df.copy()

    # --------------------------------------------------------
    # Datetime
    # --------------------------------------------------------

    df[TIME_COLUMN] = pd.to_datetime(
        df[TIME_COLUMN],
        errors="coerce"
    )

    invalid_datetime = df[TIME_COLUMN].isna().sum()

    print(
        f"Invalid/missing datetime rows: "
        f"{invalid_datetime:,}"
    )

    # --------------------------------------------------------
    # Remove invalid datetime rows
    # --------------------------------------------------------

    if invalid_datetime > 0:
        df = df.dropna(
            subset=[TIME_COLUMN]
        ).copy()

    # --------------------------------------------------------
    # Remove rows without experimental target
    # --------------------------------------------------------

    missing_target = df[TARGET_COLUMN].isna().sum()

    print(
        f"Rows without experimental condition: "
        f"{missing_target:,}"
    )

    if missing_target > 0:
        df = df.dropna(
            subset=[TARGET_COLUMN]
        ).copy()

    # --------------------------------------------------------
    # Validate animal identifiers
    # --------------------------------------------------------

    missing_pig_id = df[GROUP_COLUMN].isna().sum()

    print(
        f"Rows without pig identifier: "
        f"{missing_pig_id:,}"
    )

    if missing_pig_id > 0:
        raise ValueError(
            "Rows without pig_id cannot be safely grouped."
        )

    # --------------------------------------------------------
    # Convert behavioral variables to numeric
    # --------------------------------------------------------

    for column in BEHAVIOR_FEATURES:

        df[column] = pd.to_numeric(
            df[column],
            errors="coerce"
        )

    print(
        f"\nRows remaining after cleaning: "
        f"{len(df):,}"
    )

    print(
        f"Pigs represented: "
        f"{df[GROUP_COLUMN].nunique():,}"
    )

    print("\nTarget distribution:")
    print(
        df[TARGET_COLUMN]
        .value_counts()
        .to_string()
    )

    return df


# ============================================================
# CHECK TARGET CONSISTENCY WITHIN WINDOWS
# ============================================================

def create_window_identifier(df):
    """
    Create a 5-minute time-window identifier separately for
    each pig.

    The absolute timestamp is retained only during feature
    engineering. It is NOT written as an ML predictor.
    """

    df = df.copy()

    df["window_start"] = (
        df[TIME_COLUMN]
        .dt.floor(f"{WINDOW_MINUTES}min")
    )

    return df


# ============================================================
# AGGREGATE BEHAVIOR
# ============================================================

def aggregate_behavior(df):
    print_header(
        f"4. CREATING {WINDOW_MINUTES}-MINUTE BEHAVIOR WINDOWS"
    )

    print(
        """
Each source row represents approximately one minute of
HotPig observations.

We aggregate consecutive observations into fixed time
windows so that the ML dataset is not treated as hundreds
of thousands of independent biological samples.
"""
    )

    df = create_window_identifier(df)

    # --------------------------------------------------------
    # Grouping columns
    # --------------------------------------------------------

    group_columns = [
        GROUP_COLUMN,
        "window_start",
    ]

    # --------------------------------------------------------
    # Target consistency
    # --------------------------------------------------------

    target_per_window = (
        df.groupby(group_columns)[TARGET_COLUMN]
        .nunique()
    )

    mixed_target_windows = (
        target_per_window > 1
    ).sum()

    print(
        f"Windows containing multiple conditions: "
        f"{mixed_target_windows:,}"
    )

    if mixed_target_windows > 0:

        print(
            """
WARNING:

Some windows contain observations from more than one
experimental condition.

Those windows will NOT be assigned an arbitrary target.
They will be removed because doing otherwise would create
an ambiguous label.
"""
        )

    valid_windows = (
        target_per_window[
            target_per_window == 1
        ]
        .index
    )

    df = (
        df.set_index(group_columns)
        .loc[valid_windows]
        .reset_index()
    )

    # --------------------------------------------------------
    # Aggregation
    # --------------------------------------------------------

    aggregation_functions = {}

    for feature in BEHAVIOR_FEATURES:

        aggregation_functions[feature] = [
            "mean",
            "std",
            "min",
            "max",
        ]

    print(
        f"Behavior variables: "
        f"{len(BEHAVIOR_FEATURES)}"
    )

    print(
        "Statistics per behavior: "
        "mean, std, min, max"
    )

    feature_df = (
        df.groupby(group_columns)
        .agg(aggregation_functions)
    )

    # --------------------------------------------------------
    # Flatten MultiIndex columns
    # --------------------------------------------------------

    feature_df.columns = [
        f"{feature}_{stat}"
        for feature, stat in feature_df.columns
    ]

    feature_df = feature_df.reset_index()

    # --------------------------------------------------------
    # Add genuine target
    # --------------------------------------------------------

    target_df = (
        df.groupby(group_columns)[TARGET_COLUMN]
        .first()
        .reset_index()
    )

    feature_df = feature_df.merge(
        target_df,
        on=group_columns,
        how="left",
        validate="one_to_one",
    )

    return feature_df


# ============================================================
# REMOVE NON-INFORMATIVE FEATURES
# ============================================================

def remove_constant_features(df):
    print_header(
        "5. CHECKING FOR CONSTANT FEATURES"
    )

    feature_columns = [
        column
        for column in df.columns
        if column not in [
            GROUP_COLUMN,
            "window_start",
            TARGET_COLUMN,
        ]
    ]

    constant_features = []

    for column in feature_columns:

        if df[column].nunique(dropna=False) <= 1:
            constant_features.append(column)

    if constant_features:

        print(
            "Constant features detected:"
        )

        for column in constant_features:
            print(f"  - {column}")

        df = df.drop(
            columns=constant_features
        )

    else:

        print(
            "No constant features detected."
        )

    return df


# ============================================================
# HANDLE MISSING FEATURE VALUES
# ============================================================

def inspect_missing_features(df):
    print_header(
        "6. FEATURE MISSINGNESS AUDIT"
    )

    feature_columns = [
        column
        for column in df.columns
        if column not in [
            GROUP_COLUMN,
            "window_start",
            TARGET_COLUMN,
        ]
    ]

    missing = (
        df[feature_columns]
        .isna()
        .sum()
        .sort_values(
            ascending=False
        )
    )

    missing = missing[
        missing > 0
    ]

    if missing.empty:

        print(
            "No missing feature values."
        )

    else:

        print(
            missing.to_string()
        )

        print(
            """
Missing values are intentionally not filled here.

Imputation belongs to the training pipeline so that
statistics used for imputation are learned from training
data only.

This prevents validation/test information from leaking into
the training process.
"""
        )

    return df


# ============================================================
# CHECK CLASS DISTRIBUTION
# ============================================================

def inspect_target_distribution(df):
    print_header(
        "7. WINDOW-LEVEL TARGET DISTRIBUTION"
    )

    print(
        df[TARGET_COLUMN]
        .value_counts()
        .sort_index()
        .to_string()
    )

    print("\nPercentages:")

    percentages = (
        df[TARGET_COLUMN]
        .value_counts(
            normalize=True
        )
        .sort_index()
        * 100
    )

    print(
        percentages
        .round(3)
        .to_string()
    )


# ============================================================
# CHECK WINDOWS PER PIG
# ============================================================

def inspect_windows_per_pig(df):
    print_header(
        "8. WINDOWS PER PIG"
    )

    windows_per_pig = (
        df.groupby(GROUP_COLUMN)
        .size()
    )

    print(
        windows_per_pig
        .describe()
        .to_string()
    )

    print(
        "\nWindows by pig:"
    )

    print(
        windows_per_pig
        .sort_index()
        .to_string()
    )


# ============================================================
# CHECK TARGET COVERAGE PER PIG
# ============================================================

def inspect_target_by_pig(df):
    print_header(
        "9. TARGET COVERAGE BY PIG"
    )

    table = pd.crosstab(
        df[GROUP_COLUMN],
        df[TARGET_COLUMN],
    )

    print(
        table.to_string()
    )

    number_of_classes = (
        table.gt(0)
        .sum(axis=1)
    )

    print(
        "\nNumber of target classes represented per pig:"
    )

    print(
        number_of_classes
        .value_counts()
        .sort_index()
        .to_string()
    )

    if (number_of_classes < 4).any():

        print(
            """
NOTE:

Some pigs do not contain all four experimental conditions
after window construction.

This does not mean the data is wrong. It must simply be
considered when constructing grouped train/test splits.
"""
        )


# ============================================================
# CHECK FEATURE/TARGET RELATIONSHIPS
# ============================================================

def inspect_feature_statistics(df):
    print_header(
        "10. FEATURE STATISTICS BY EXPERIMENTAL CONDITION"
    )

    feature_columns = [
        column
        for column in df.columns
        if column not in [
            GROUP_COLUMN,
            "window_start",
            TARGET_COLUMN,
        ]
    ]

    summary = (
        df.groupby(TARGET_COLUMN)[feature_columns]
        .mean()
        .T
    )

    print(
        summary.to_string()
    )


# ============================================================
# VERIFY NO FORBIDDEN PREDICTORS
# ============================================================

def verify_no_leakage_columns(df):
    print_header(
        "11. FINAL LEAKAGE COLUMN CHECK"
    )

    forbidden_predictors = [
        "datetime",
        "period",
        "conditions",
        "pig_id",
        "source_dataset",
        "state",
        "unknown",
    ]

    feature_columns = set(
        df.columns
    )

    found = [
        column
        for column in forbidden_predictors
        if column in feature_columns
        and column not in [
            GROUP_COLUMN,
            TARGET_COLUMN,
        ]
    ]

    # pig_id is intentionally retained as group metadata.
    # conditions is intentionally retained as target metadata.
    #
    # Neither is part of the feature matrix.
    #
    # We therefore perform a second explicit check.

    ml_features = [
        column
        for column in df.columns
        if column not in [
            GROUP_COLUMN,
            "window_start",
            TARGET_COLUMN,
        ]
    ]

    forbidden_ml_features = [
        column
        for column in [
            "datetime",
            "period",
            "conditions",
            "source_dataset",
            "state",
            "unknown",
            "pig_id",
        ]
        if column in ml_features
    ]

    if forbidden_ml_features:

        raise ValueError(
            "Forbidden columns were found in the ML feature set:\n"
            + "\n".join(forbidden_ml_features)
        )

    print(
        "No forbidden leakage variables are included "
        "in the ML feature columns."
    )

    print(
        "\nMetadata retained:"
    )

    print(
        f"  - {GROUP_COLUMN}: grouping/evaluation only"
    )

    print(
        f"  - window_start: traceability only"
    )

    print(
        f"  - {TARGET_COLUMN}: genuine experimental target"
    )


# ============================================================
# SAVE DATASET
# ============================================================

def save_dataset(df):
    print_header(
        "12. SAVING ML-READY HOTPIG DATASET"
    )

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True
    )

    df.to_csv(
        OUTPUT_FILE,
        index=False
    )

    print(
        f"Rows saved: {len(df):,}"
    )

    print(
        f"Columns saved: {len(df.columns)}"
    )

    print(
        f"\nOutput:\n{OUTPUT_FILE}"
    )


# ============================================================
# FINAL SCHEMA
# ============================================================

def print_final_schema(df):
    print_header(
        "13. FINAL DATASET SCHEMA"
    )

    for index, column in enumerate(
        df.columns,
        start=1
    ):
        print(
            f"{index:>3}. {column}"
        )

    print(
        """
The saved dataset contains three types of information:

1. GROUPING METADATA
   pig_id

2. TRACEABILITY METADATA
   window_start

3. ML TARGET
   conditions

4. ML FEATURES
   behavioral window statistics

pig_id and window_start must NOT be supplied to the model.
"""
    )


# ============================================================
# MAIN
# ============================================================

def main():

    print("\n")
    print("#" * 80)
    print("# PRISM ML - HOTPIG FEATURE ENGINEERING")
    print("#")
    print("# Purpose:")
    print("#   Convert genuine one-minute HotPig observations into")
    print("#   a leakage-conscious, window-level ML dataset.")
    print("#")
    print("# This script DOES NOT:")
    print("#   - create synthetic observations")
    print("#   - create PRISM labels")
    print("#   - train a model")
    print("#   - merge datasets")
    print("#   - use pig identity as a predictor")
    print("#   - use experimental schedule as a predictor")
    print("#" * 80)

    df = load_data()

    validate_source(
        df
    )

    df = clean_source(
        df
    )

    df = aggregate_behavior(
        df
    )

    df = remove_constant_features(
        df
    )

    inspect_missing_features(
        df
    )

    inspect_target_distribution(
        df
    )

    inspect_windows_per_pig(
        df
    )

    inspect_target_by_pig(
        df
    )

    inspect_feature_statistics(
        df
    )

    verify_no_leakage_columns(
        df
    )

    print_final_schema(
        df
    )

    save_dataset(
        df
    )

    print_header(
        "FEATURE ENGINEERING COMPLETE"
    )

    print(
        """
The HotPig ML dataset has been created.

No synthetic observations were created.
No synthetic labels were created.
No PRISM risk labels were created.
No model was trained.

The next stage should perform the grouped train/test
split and establish a genuine ML baseline using unseen pigs.
"""
    )


if __name__ == "__main__":
    main()