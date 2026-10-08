"""
INRAE physiological feature engineering.

Purpose
-------
Convert the genuine INRAE high-frequency measurements into
animal-aware temporal windows suitable for ML experiments.

Important:
- No synthetic observations.
- No synthetic labels.
- No PRISM risk labels.
- No deterministic prediction rules.
- Pig identity is retained only as grouping metadata.
- Experimental period remains the genuine experimental target.
- Experimental schedule variables are not ML predictors.

The resulting dataset is intended for subsequent ML evaluation.

Input:
    data/processed/inrae/inrae_processed.csv

Output:
    data/processed/inrae/inrae_ml_features_30min.csv
"""

from pathlib import Path

import numpy as np
import pandas as pd


# =====================================================================
# PATHS
# =====================================================================

PROJECT_ROOT = Path(__file__).resolve().parents[2]

INPUT_FILE = (
    PROJECT_ROOT
    / "data"
    / "processed"
    / "inrae"
    / "inrae_processed.csv"
)

OUTPUT_DIR = (
    PROJECT_ROOT
    / "data"
    / "processed"
    / "inrae"
)

OUTPUT_FILE = (
    OUTPUT_DIR
    / "inrae_ml_features_30min.csv"
)


# =====================================================================
# CONFIGURATION
# =====================================================================

WINDOW_MINUTES = 30

TARGET_COLUMN = "periode"

GROUP_COLUMN = "porc"

TIME_COLUMN = "datetime"


# Genuine measurements that may be used as predictors.
NUMERIC_FEATURES = [
    "T_IM",
    "T",
    "age",
    "ADFI",
]


# Categorical feature retained for potential ML use.
CATEGORICAL_FEATURES = [
    "stage",
]


# Variables that must never become predictors.
EXCLUDED_COLUMNS = {
    TARGET_COLUMN,
    GROUP_COLUMN,
    TIME_COLUMN,
    "id_challenge",
    "ordre_challenge",
    "date_stress",
    "jour_debut_stress",
    "temps_relatif_jour",
}


# =====================================================================
# HELPER
# =====================================================================

def safe_numeric(
    series: pd.Series,
) -> pd.Series:

    return pd.to_numeric(
        series,
        errors="coerce",
    )


# =====================================================================
# MAIN
# =====================================================================

def main():

    print("=" * 70)
    print("INRAE Physiological Feature Engineering")
    print("=" * 70)

    print(
        f"\nProject root : {PROJECT_ROOT}"
    )

    print(
        f"Input file   : {INPUT_FILE}"
    )

    print(
        f"Output file  : {OUTPUT_FILE}"
    )

    # -----------------------------------------------------------------
    # LOAD
    # -----------------------------------------------------------------

    print(
        "\n[1/9] Loading genuine INRAE data..."
    )

    if not INPUT_FILE.exists():

        raise FileNotFoundError(
            f"Input file not found:\n{INPUT_FILE}"
        )

    df = pd.read_csv(
        INPUT_FILE,
        low_memory=False,
    )

    print(
        f"Rows loaded    : {len(df):,}"
    )

    print(
        f"Columns loaded : {len(df.columns):,}"
    )

    # -----------------------------------------------------------------
    # VALIDATE
    # -----------------------------------------------------------------

    print(
        "\n[2/9] Validating required columns..."
    )

    required_columns = [
        TIME_COLUMN,
        GROUP_COLUMN,
        TARGET_COLUMN,
        *NUMERIC_FEATURES,
        *CATEGORICAL_FEATURES,
    ]

    missing_columns = [
        column
        for column in required_columns
        if column not in df.columns
    ]

    if missing_columns:

        raise ValueError(
            "Missing required columns:\n"
            + "\n".join(
                f"  - {column}"
                for column in missing_columns
            )
        )

    print(
        "All required columns are present."
    )

    # -----------------------------------------------------------------
    # PARSE TIME
    # -----------------------------------------------------------------

    print(
        "\n[3/9] Parsing timestamps..."
    )

    df[TIME_COLUMN] = pd.to_datetime(
        df[TIME_COLUMN],
        errors="coerce",
    )

    invalid_time = int(
        df[TIME_COLUMN].isna().sum()
    )

    print(
        f"Invalid timestamps: "
        f"{invalid_time:,}"
    )

    if invalid_time > 0:

        print(
            "Removing observations with invalid timestamps."
        )

        df = df.dropna(
            subset=[TIME_COLUMN]
        ).copy()

    # -----------------------------------------------------------------
    # REMOVE MISSING TARGET / PIG
    # -----------------------------------------------------------------

    print(
        "\n[4/9] Removing observations without "
        "genuine target or animal identity..."
    )

    before = len(df)

    df = df.dropna(
        subset=[
            TARGET_COLUMN,
            GROUP_COLUMN,
        ]
    ).copy()

    removed = before - len(df)

    print(
        f"Rows removed: {removed:,}"
    )

    print(
        "\nExperimental target counts:"
    )

    print(
        df[TARGET_COLUMN]
        .value_counts()
        .to_string()
    )

    # -----------------------------------------------------------------
    # NUMERIC CONVERSION
    # -----------------------------------------------------------------

    print(
        "\n[5/9] Converting numerical measurements..."
    )

    for column in NUMERIC_FEATURES:

        df[column] = safe_numeric(
            df[column]
        )

    # Stage is retained as numeric because the source represents
    # stage using numerical values.
    df["stage"] = safe_numeric(
        df["stage"]
    )

    # -----------------------------------------------------------------
    # SORT
    # -----------------------------------------------------------------

    print(
        "\n[6/9] Sorting observations by pig and time..."
    )

    df = df.sort_values(
        [
            GROUP_COLUMN,
            TIME_COLUMN,
        ]
    ).reset_index(
        drop=True
    )

    # -----------------------------------------------------------------
    # CREATE TIME WINDOWS
    # -----------------------------------------------------------------

    print(
        f"\n[7/9] Creating "
        f"{WINDOW_MINUTES}-minute windows..."
    )

    # Floor timestamps to fixed 30-minute windows.
    df["window_start"] = (
        df[TIME_COLUMN]
        .dt.floor(
            f"{WINDOW_MINUTES}min"
        )
    )

    # ---------------------------------------------------------------
    # Check whether a window contains more than one experimental
    # period. Such windows are removed rather than assigning a
    # synthetic target.
    # ---------------------------------------------------------------

    target_counts = (
        df.groupby(
            [
                GROUP_COLUMN,
                "window_start",
            ],
            observed=True,
        )[TARGET_COLUMN]
        .nunique()
    )

    mixed_windows = (
        target_counts > 1
    )

    mixed_count = int(
        mixed_windows.sum()
    )

    print(
        f"Mixed-target windows: "
        f"{mixed_count:,}"
    )

    if mixed_count > 0:

        mixed_index = (
            target_counts[
                mixed_windows
            ]
            .index
        )

        mixed_keys = set(
            mixed_index
        )

        window_keys = list(
            zip(
                df[GROUP_COLUMN],
                df["window_start"],
            )
        )

        keep_mask = [
            key not in mixed_keys
            for key in window_keys
        ]

        df = df.loc[
            keep_mask
        ].copy()

        print(
            "Mixed-target windows removed."
        )

    else:

        print(
            "No mixed-target windows detected."
        )

    # -----------------------------------------------------------------
    # AGGREGATION
    # -----------------------------------------------------------------

    print(
        "\nGenerating physiological features..."
    )

    group_columns = [
        GROUP_COLUMN,
        "window_start",
    ]

    feature_frames = []

    # ---------------------------------------------------------------
    # T_IM FEATURES
    # ---------------------------------------------------------------

    tim_group = df.groupby(
        group_columns,
        observed=True,
    )["T_IM"]

    tim_features = pd.DataFrame(
        {
            "T_IM_mean": tim_group.mean(),
            "T_IM_std": tim_group.std(),
            "T_IM_min": tim_group.min(),
            "T_IM_max": tim_group.max(),
            "T_IM_median": tim_group.median(),
            "T_IM_q25": tim_group.quantile(0.25),
            "T_IM_q75": tim_group.quantile(0.75),
        }
    )

    tim_features[
        "T_IM_range"
    ] = (
        tim_features["T_IM_max"]
        - tim_features["T_IM_min"]
    )

    feature_frames.append(
        tim_features
    )

    # ---------------------------------------------------------------
    # ENVIRONMENTAL TEMPERATURE
    # ---------------------------------------------------------------

    t_group = df.groupby(
        group_columns,
        observed=True,
    )["T"]

    t_features = pd.DataFrame(
        {
            "T_mean": t_group.mean(),
            "T_std": t_group.std(),
            "T_min": t_group.min(),
            "T_max": t_group.max(),
            "T_median": t_group.median(),
            "T_q25": t_group.quantile(0.25),
            "T_q75": t_group.quantile(0.75),
        }
    )

    t_features[
        "T_range"
    ] = (
        t_features["T_max"]
        - t_features["T_min"]
    )

    feature_frames.append(
        t_features
    )

    # ---------------------------------------------------------------
    # AGE
    # ---------------------------------------------------------------

    age_group = df.groupby(
        group_columns,
        observed=True,
    )["age"]

    age_features = pd.DataFrame(
        {
            "age_mean": age_group.mean(),
        }
    )

    feature_frames.append(
        age_features
    )

    # ---------------------------------------------------------------
    # ADFI
    # ---------------------------------------------------------------

    adfi_group = df.groupby(
        group_columns,
        observed=True,
    )["ADFI"]

    adfi_features = pd.DataFrame(
        {
            "ADFI_mean": adfi_group.mean(),
            "ADFI_std": adfi_group.std(),
        }
    )

    feature_frames.append(
        adfi_features
    )

    # ---------------------------------------------------------------
    # STAGE
    # ---------------------------------------------------------------

    stage_group = df.groupby(
        group_columns,
        observed=True,
    )["stage"]

    stage_features = pd.DataFrame(
        {
            "stage_mean": stage_group.mean(),
        }
    )

    feature_frames.append(
        stage_features
    )

    # ---------------------------------------------------------------
    # WITHIN-PIG TEMPORAL FEATURES
    # ---------------------------------------------------------------

    print(
        "Generating temporal physiological features..."
    )

    # We first create one chronological window-level T_IM series.
    #
    # This allows the model to see genuine physiological change
    # without using experimental schedule variables.

    window_tim = (
        df.groupby(
            group_columns,
            observed=True,
        )["T_IM"]
        .mean()
        .rename(
            "window_T_IM_mean"
        )
        .reset_index()
    )

    window_tim = window_tim.sort_values(
        [
            GROUP_COLUMN,
            "window_start",
        ]
    )

    window_tim[
        "T_IM_change"
    ] = (
        window_tim
        .groupby(
            GROUP_COLUMN
        )["window_T_IM_mean"]
        .diff()
    )

    window_tim[
        "T_IM_abs_change"
    ] = (
        window_tim[
            "T_IM_change"
        ]
        .abs()
    )

    window_tim[
        "T_IM_change_direction"
    ] = np.sign(
        window_tim[
            "T_IM_change"
        ]
    )

    # Rolling variability of the preceding three windows.
    #
    # This remains a genuine measurement-derived feature and does
    # not use the experimental target.

    window_tim[
        "T_IM_rolling_mean_3"
    ] = (
        window_tim
        .groupby(
            GROUP_COLUMN
        )["window_T_IM_mean"]
        .transform(
            lambda s:
                s.rolling(
                    3,
                    min_periods=1,
                ).mean()
        )
    )

    window_tim[
        "T_IM_rolling_std_3"
    ] = (
        window_tim
        .groupby(
            GROUP_COLUMN
        )["window_T_IM_mean"]
        .transform(
            lambda s:
                s.rolling(
                    3,
                    min_periods=2,
                ).std()
        )
    )

    temporal_features = (
        window_tim[
            [
                GROUP_COLUMN,
                "window_start",
                "T_IM_change",
                "T_IM_abs_change",
                "T_IM_change_direction",
                "T_IM_rolling_mean_3",
                "T_IM_rolling_std_3",
            ]
        ]
        .set_index(
            group_columns
        )
    )

    feature_frames.append(
        temporal_features
    )

    # -----------------------------------------------------------------
    # COMBINE FEATURES
    # -----------------------------------------------------------------

    print(
        "Combining feature groups..."
    )

    features = pd.concat(
        feature_frames,
        axis=1,
    )

    features = (
        features
        .reset_index()
    )

    # -----------------------------------------------------------------
    # ADD TARGET
    # -----------------------------------------------------------------

    target_per_window = (
        df.groupby(
            group_columns,
            observed=True,
        )[TARGET_COLUMN]
        .first()
        .reset_index()
    )

    features = features.merge(
        target_per_window,
        on=group_columns,
        how="inner",
        validate="one_to_one",
    )

    # -----------------------------------------------------------------
    # VALIDATE
    # -----------------------------------------------------------------

    print(
        "\n[8/9] Validating generated dataset..."
    )

    feature_columns = [
        column
        for column in features.columns
        if column not in {
            TARGET_COLUMN,
            GROUP_COLUMN,
            "window_start",
        }
    ]

    print(
        f"Rows/windows      : "
        f"{len(features):,}"
    )

    print(
        f"Number of pigs    : "
        f"{features[GROUP_COLUMN].nunique():,}"
    )

    print(
        f"Number of ML features: "
        f"{len(feature_columns):,}"
    )

    print(
        "\nTarget counts:"
    )

    print(
        features[TARGET_COLUMN]
        .value_counts()
        .to_string()
    )

    # Check that no forbidden columns slipped through.
    forbidden = (
        set(feature_columns)
        & EXCLUDED_COLUMNS
    )

    if forbidden:

        raise ValueError(
            "Forbidden columns found in "
            f"ML features: {sorted(forbidden)}"
        )

    # Check numeric features.
    non_numeric = [
        column
        for column in feature_columns
        if not pd.api.types.is_numeric_dtype(
            features[column]
        )
    ]

    if non_numeric:

        raise ValueError(
            "Non-numeric ML features found:\n"
            + "\n".join(
                f"  - {column}"
                for column in non_numeric
            )
        )

    missing_feature_values = int(
        features[
            feature_columns
        ]
        .isna()
        .sum()
        .sum()
    )

    print(
        f"Missing ML feature values: "
        f"{missing_feature_values:,}"
    )

    # -----------------------------------------------------------------
    # SAVE
    # -----------------------------------------------------------------

    print(
        "\n[9/9] Saving feature dataset..."
    )

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    features.to_csv(
        OUTPUT_FILE,
        index=False,
    )

    print(
        f"\nSaved successfully:\n"
        f"{OUTPUT_FILE}"
    )

    print(
        "\n" + "=" * 70
    )

    print(
        "INRAE feature engineering completed."
    )

    print(
        "=" * 70
    )


if __name__ == "__main__":
    main()