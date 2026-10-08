"""
Optimized temporal feature engineering for the genuine HotPig dataset.

Purpose
-------
Create a richer temporal feature representation from the genuine HotPig
one-minute behavioral observations.

Important constraints
---------------------
- Uses only genuine HotPig observations.
- Does NOT create synthetic observations.
- Does NOT create synthetic labels.
- Does NOT use deterministic rules to create labels.
- Does NOT use experimental schedule variables as predictors.
- Does NOT use pig identity as a predictor.
- Keeps the original HotPig experimental condition as the target.
- Uses pig_id only for grouping and traceability.
- Uses only observations within each 5-minute window.

Input
-----
data/processed/hotpig/hotpig_processed.csv

Output
------
data/processed/hotpig/hotpig_temporal_ml_features_5min.csv
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
    / "hotpig"
    / "hotpig_processed.csv"
)

OUTPUT_FILE = (
    PROJECT_ROOT
    / "data"
    / "processed"
    / "hotpig"
    / "hotpig_temporal_ml_features_5min.csv"
)


# =====================================================================
# CONFIGURATION
# =====================================================================

TIME_COLUMN = "datetime"
TARGET_COLUMN = "conditions"
GROUP_COLUMN = "pig_id"

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

VALID_TARGETS = {
    "TN",
    "TU",
    "HS",
    "TD",
}


# =====================================================================
# HELPER FUNCTIONS
# =====================================================================

def calculate_slope(group: pd.DataFrame, column: str) -> float:
    """
    Calculate the linear trend of one behavioral feature within
    one 5-minute window.

    The x-axis is simply observation order within the window.

    This is a descriptive temporal feature. It is NOT a deterministic
    health or risk rule.
    """

    values = pd.to_numeric(
        group[column],
        errors="coerce",
    ).to_numpy(dtype=float)

    valid = np.isfinite(values)

    if valid.sum() < 2:
        return np.nan

    y = values[valid]
    x = np.arange(len(values), dtype=float)[valid]

    # Center x and y to improve numerical stability.
    x_centered = x - x.mean()
    y_centered = y - y.mean()

    denominator = np.sum(x_centered ** 2)

    if denominator == 0:
        return 0.0

    return float(
        np.sum(x_centered * y_centered) / denominator
    )


# =====================================================================
# MAIN
# =====================================================================

def main():

    print("=" * 70)
    print("HotPig Optimized Temporal Feature Engineering")
    print("=" * 70)

    print(f"\nProject root : {PROJECT_ROOT}")
    print(f"Input file   : {INPUT_FILE}")
    print(f"Output file  : {OUTPUT_FILE}")

    # -----------------------------------------------------------------
    # LOAD
    # -----------------------------------------------------------------

    print("\n[1/8] Loading HotPig processed data...")

    if not INPUT_FILE.exists():
        raise FileNotFoundError(
            f"Input file does not exist:\n{INPUT_FILE}"
        )

    df = pd.read_csv(INPUT_FILE)

    print(f"Rows loaded    : {len(df):,}")
    print(f"Columns loaded : {len(df.columns)}")

    # -----------------------------------------------------------------
    # VALIDATE COLUMNS
    # -----------------------------------------------------------------

    print("\n[2/8] Validating required columns...")

    required_columns = [
        TIME_COLUMN,
        TARGET_COLUMN,
        GROUP_COLUMN,
        *BEHAVIOR_FEATURES,
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

    print("All required columns are present.")

    # -----------------------------------------------------------------
    # DATETIME
    # -----------------------------------------------------------------

    print("\n[3/8] Parsing timestamps...")

    df[TIME_COLUMN] = pd.to_datetime(
        df[TIME_COLUMN],
        errors="coerce",
    )

    invalid_datetime = int(
        df[TIME_COLUMN].isna().sum()
    )

    print(
        f"Invalid timestamps: {invalid_datetime:,}"
    )

    if invalid_datetime > 0:
        df = df.dropna(
            subset=[
                TIME_COLUMN,
                GROUP_COLUMN,
                TARGET_COLUMN,
            ]
        )

    # -----------------------------------------------------------------
    # TARGET
    # -----------------------------------------------------------------

    print(
        "\n[4/8] Removing observations without "
        "a genuine experimental target..."
    )

    before = len(df)

    df = df.dropna(
        subset=[TARGET_COLUMN]
    )

    removed = before - len(df)

    print(
        "Rows removed because condition was missing: "
        f"{removed:,}"
    )

    observed_targets = set(
        df[TARGET_COLUMN]
        .dropna()
        .unique()
    )

    unexpected_targets = (
        observed_targets - VALID_TARGETS
    )

    if unexpected_targets:
        raise ValueError(
            "Unexpected target values found: "
            f"{sorted(unexpected_targets)}"
        )

    print(
        "Target classes:",
        sorted(observed_targets)
    )

    print("\nTarget counts:")

    print(
        df[TARGET_COLUMN]
        .value_counts()
        .sort_index()
        .to_string()
    )

    # -----------------------------------------------------------------
    # SORT
    # -----------------------------------------------------------------

    print(
        "\n[5/8] Sorting observations by pig and time..."
    )

    df = df.sort_values(
        [
            GROUP_COLUMN,
            TIME_COLUMN,
        ]
    ).reset_index(drop=True)

    # -----------------------------------------------------------------
    # CREATE WINDOW
    # -----------------------------------------------------------------

    print(
        "\n[6/8] Creating 5-minute temporal windows..."
    )

    df["window_start"] = (
        df[TIME_COLUMN]
        .dt.floor("5min")
    )

    # -----------------------------------------------------------------
    # MIXED TARGET CHECK
    # -----------------------------------------------------------------

    print(
        "\nChecking for mixed-target windows..."
    )

    window_target_counts = (
        df.groupby(
            [
                GROUP_COLUMN,
                "window_start",
            ],
            observed=True,
            sort=False,
        )[TARGET_COLUMN]
        .nunique()
    )

    mixed_window_index = (
        window_target_counts[
            window_target_counts > 1
        ]
        .index
    )

    mixed_count = len(mixed_window_index)

    print(
        f"Mixed-target windows detected: "
        f"{mixed_count:,}"
    )

    if mixed_count > 0:

        print(
            "Removing mixed-target windows..."
        )

        mixed_keys = pd.MultiIndex.from_tuples(
            mixed_window_index,
            names=[
                GROUP_COLUMN,
                "window_start",
            ],
        )

        current_keys = pd.MultiIndex.from_frame(
            df[
                [
                    GROUP_COLUMN,
                    "window_start",
                ]
            ]
        )

        keep_mask = ~current_keys.isin(
            mixed_keys
        )

        df = df.loc[
            keep_mask
        ].copy()

        print(
            f"Rows remaining after removal: "
            f"{len(df):,}"
        )

    else:
        print(
            "No mixed-target windows detected."
        )

    # -----------------------------------------------------------------
    # VECTORIZED BASE FEATURES
    # -----------------------------------------------------------------

    print(
        "\nGenerating vectorized temporal features..."
    )

    group_columns = [
        GROUP_COLUMN,
        "window_start",
    ]

    grouped = df.groupby(
        group_columns,
        observed=True,
        sort=False,
    )

    # -----------------------------------------------------------------
    # Basic statistics
    #
    # These replace the slower per-group Python function.
    # -----------------------------------------------------------------

    print(
        "  - Calculating level statistics..."
    )

    aggregation_functions = [
        "mean",
        "std",
        "min",
        "max",
        "median",
    ]

    aggregated = grouped[
        BEHAVIOR_FEATURES
    ].agg(
        aggregation_functions
    )

    # Flatten MultiIndex columns.
    aggregated.columns = [
        f"{feature}_{stat}"
        for feature, stat
        in aggregated.columns
    ]

    # -----------------------------------------------------------------
    # Quantiles
    # -----------------------------------------------------------------

    print(
        "  - Calculating quantiles..."
    )

    q25 = (
        grouped[
            BEHAVIOR_FEATURES
        ]
        .quantile(0.25)
    )

    q25.columns = [
        f"{feature}_q25"
        for feature in BEHAVIOR_FEATURES
    ]

    q75 = (
        grouped[
            BEHAVIOR_FEATURES
        ]
        .quantile(0.75)
    )

    q75.columns = [
        f"{feature}_q75"
        for feature in BEHAVIOR_FEATURES
    ]

    # -----------------------------------------------------------------
    # Combine basic statistics.
    # -----------------------------------------------------------------

    features = pd.concat(
        [
            aggregated,
            q25,
            q75,
        ],
        axis=1,
    )

    # -----------------------------------------------------------------
    # RANGE
    # -----------------------------------------------------------------

    print(
        "  - Calculating ranges..."
    )

    for feature in BEHAVIOR_FEATURES:

        features[
            f"{feature}_range"
        ] = (
            features[
                f"{feature}_max"
            ]
            - features[
                f"{feature}_min"
            ]
        )

    # -----------------------------------------------------------------
    # TEMPORAL DIFFERENCES
    #
    # Because the original data are already sorted by pig/time,
    # diff() represents change between consecutive genuine
    # observations.
    # -----------------------------------------------------------------

    print(
        "  - Calculating temporal changes..."
    )

    for feature in BEHAVIOR_FEATURES:

        difference = (
            df.groupby(
                group_columns,
                observed=True,
                sort=False,
            )[feature]
            .diff()
        )

        df[
            f"__{feature}_diff"
        ] = difference

    diff_columns = [
        f"__{feature}_diff"
        for feature in BEHAVIOR_FEATURES
    ]

    diff_grouped = df.groupby(
        group_columns,
        observed=True,
        sort=False,
    )

    diff_stats = diff_grouped[
        diff_columns
    ].agg(
        [
            "mean",
            "std",
        ]
    )

    # Flatten names.
    flattened_diff_stats = []

    for column, stat in diff_stats.columns:

        feature = column.replace(
            "__",
            "",
            1,
        ).replace(
            "_diff",
            "",
            1,
        )

        flattened_diff_stats.append(
            f"{feature}_diff_{stat}"
        )

    diff_stats.columns = (
        flattened_diff_stats
    )

    features = pd.concat(
        [
            features,
            diff_stats,
        ],
        axis=1,
    )

    # -----------------------------------------------------------------
    # ABSOLUTE DIFFERENCES
    # -----------------------------------------------------------------

    print(
        "  - Calculating absolute changes..."
    )

    for feature in BEHAVIOR_FEATURES:

        diff_column = (
            f"__{feature}_diff"
        )

        df[
            f"__{feature}_absdiff"
        ] = df[
            diff_column
        ].abs()

    absdiff_columns = [
        f"__{feature}_absdiff"
        for feature in BEHAVIOR_FEATURES
    ]

    absdiff_stats = (
        df.groupby(
            group_columns,
            observed=True,
            sort=False,
        )[absdiff_columns]
        .agg(
            [
                "mean",
                "std",
            ]
        )
    )

    flattened_absdiff_stats = []

    for column, stat in absdiff_stats.columns:

        feature = column.replace(
            "__",
            "",
            1,
        ).replace(
            "_absdiff",
            "",
            1,
        )

        flattened_absdiff_stats.append(
            f"{feature}_absdiff_{stat}"
        )

    absdiff_stats.columns = (
        flattened_absdiff_stats
    )

    features = pd.concat(
        [
            features,
            absdiff_stats,
        ],
        axis=1,
    )

    # -----------------------------------------------------------------
    # CHANGE DIRECTION
    # -----------------------------------------------------------------

    print(
        "  - Calculating change-direction features..."
    )

    direction_frames = []

    for feature in BEHAVIOR_FEATURES:

        diff_column = (
            f"__{feature}_diff"
        )

        temp = df[
            [
                *group_columns,
                diff_column,
            ]
        ].copy()

        temp[
            "__positive"
        ] = (
            temp[diff_column] > 0
        ).astype(float)

        temp[
            "__negative"
        ] = (
            temp[diff_column] < 0
        ).astype(float)

        temp[
            "__zero"
        ] = (
            temp[diff_column] == 0
        ).astype(float)

        direction = (
            temp.groupby(
                group_columns,
                observed=True,
                sort=False,
            )[
                [
                    "__positive",
                    "__negative",
                    "__zero",
                ]
            ]
            .mean()
        )

        direction.columns = [
            f"{feature}_positive_change_fraction",
            f"{feature}_negative_change_fraction",
            f"{feature}_zero_change_fraction",
        ]

        direction_frames.append(
            direction
        )

    direction_features = pd.concat(
        direction_frames,
        axis=1,
    )

    features = pd.concat(
        [
            features,
            direction_features,
        ],
        axis=1,
    )

    # -----------------------------------------------------------------
    # TEMPORAL SLOPES
    #
    # Slope is the only feature here that requires a Python-level
    # group operation. It is calculated once per feature rather than
    # running a large multi-feature function for every group.
    # -----------------------------------------------------------------

    print(
        "  - Calculating temporal trends..."
    )

    slope_frames = []

    for feature in BEHAVIOR_FEATURES:

        slope_series = (
            df.groupby(
                group_columns,
                observed=True,
                sort=False,
            )
            .apply(
                lambda group: calculate_slope(
                    group,
                    feature,
                ),
                include_groups=False,
            )
        )

        slope_series.name = (
            f"{feature}_slope"
        )

        slope_frames.append(
            slope_series
        )

    slopes = pd.concat(
        slope_frames,
        axis=1,
    )

    features = pd.concat(
        [
            features,
            slopes,
        ],
        axis=1,
    )

    # -----------------------------------------------------------------
    # RESET INDEX
    # -----------------------------------------------------------------

    features = features.reset_index()

    # -----------------------------------------------------------------
    # ADD TARGET
    # -----------------------------------------------------------------

    print(
        "  - Adding genuine experimental target..."
    )

    targets = (
        df.groupby(
            group_columns,
            observed=True,
            sort=False,
        )[TARGET_COLUMN]
        .first()
        .reset_index()
    )

    features = features.merge(
        targets,
        on=group_columns,
        how="left",
        validate="one_to_one",
    )

    # -----------------------------------------------------------------
    # CLEAN TEMPORARY COLUMNS
    # -----------------------------------------------------------------

    temporary_columns = [
        column
        for column in df.columns
        if column.startswith("__")
    ]

    if temporary_columns:
        df.drop(
            columns=temporary_columns,
            inplace=True,
        )

    # -----------------------------------------------------------------
    # VALIDATION
    # -----------------------------------------------------------------

    print(
        "\n[7/8] Validating temporal feature dataset..."
    )

    if features.empty:
        raise ValueError(
            "Generated feature dataset is empty."
        )

    expected_metadata = {
        GROUP_COLUMN,
        "window_start",
        TARGET_COLUMN,
    }

    missing_metadata = (
        expected_metadata
        - set(features.columns)
    )

    if missing_metadata:
        raise ValueError(
            "Missing required metadata columns: "
            f"{sorted(missing_metadata)}"
        )

    # Target validation.
    output_targets = set(
        features[TARGET_COLUMN]
        .dropna()
        .unique()
    )

    if output_targets != VALID_TARGETS:
        raise ValueError(
            "Unexpected output target classes: "
            f"{sorted(output_targets)}"
        )

    # Duplicate window validation.
    duplicate_windows = int(
        features.duplicated(
            subset=[
                GROUP_COLUMN,
                "window_start",
            ]
        ).sum()
    )

    if duplicate_windows:
        raise ValueError(
            "Duplicate pig/window rows found: "
            f"{duplicate_windows}"
        )

    # -----------------------------------------------------------------
    # Predictor validation
    # -----------------------------------------------------------------

    forbidden_predictors = {
        TARGET_COLUMN,
        TIME_COLUMN,
        "period",
        "pig_id",
        "source_dataset",
        "state",
        "unknown",
        "date_stress",
        "jour_debut_stress",
        "id_challenge",
        "ordre_challenge",
        "porc",
    }

    predictor_columns = [
        column
        for column in features.columns
        if column not in expected_metadata
    ]

    forbidden_found = (
        set(predictor_columns)
        & forbidden_predictors
    )

    if forbidden_found:
        raise ValueError(
            "Forbidden predictor columns detected: "
            f"{sorted(forbidden_found)}"
        )

    # -----------------------------------------------------------------
    # Check numeric predictors
    # -----------------------------------------------------------------

    non_numeric_predictors = [
        column
        for column in predictor_columns
        if not pd.api.types.is_numeric_dtype(
            features[column]
        )
    ]

    if non_numeric_predictors:
        raise ValueError(
            "Non-numeric ML predictors detected: "
            f"{non_numeric_predictors}"
        )

    # -----------------------------------------------------------------
    # Report
    # -----------------------------------------------------------------

    print("\nGenerated target counts:")

    print(
        features[TARGET_COLUMN]
        .value_counts()
        .sort_index()
        .to_string()
    )

    print(
        f"\nNumber of pigs: "
        f"{features[GROUP_COLUMN].nunique():,}"
    )

    print(
        f"Number of 5-minute windows: "
        f"{len(features):,}"
    )

    print(
        f"Number of ML features: "
        f"{len(predictor_columns):,}"
    )

    missing_values = int(
        features[predictor_columns]
        .isna()
        .sum()
        .sum()
    )

    print(
        f"Missing ML feature values: "
        f"{missing_values:,}"
    )

    print(
        "\nFeature groups generated:"
    )

    print(
        "  - Mean"
    )
    print(
        "  - Standard deviation"
    )
    print(
        "  - Minimum"
    )
    print(
        "  - Maximum"
    )
    print(
        "  - Median"
    )
    print(
        "  - 25th percentile"
    )
    print(
        "  - 75th percentile"
    )
    print(
        "  - Range"
    )
    print(
        "  - Temporal difference"
    )
    print(
        "  - Absolute temporal difference"
    )
    print(
        "  - Change direction"
    )
    print(
        "  - Temporal slope"
    )

    # -----------------------------------------------------------------
    # SAVE
    # -----------------------------------------------------------------

    print(
        "\n[8/8] Saving temporal feature dataset..."
    )

    OUTPUT_FILE.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    features.to_csv(
        OUTPUT_FILE,
        index=False,
    )

    print(
        f"\nSaved successfully:\n{OUTPUT_FILE}"
    )

    print("\n" + "=" * 70)
    print(
        "Temporal feature engineering completed successfully."
    )
    print("=" * 70)


# =====================================================================
# ENTRY POINT
# =====================================================================

if __name__ == "__main__":
    main()