"""
INRAE Engineered Feature Audit
================================

Purpose
-------
Audit the engineered INRAE 30-minute physiological dataset before
training an ML model.

This script DOES NOT:
- train a model
- create synthetic observations
- create synthetic labels
- modify the dataset
- create PRISM risk labels
- map experimental periods to PRISM risk classes

It checks whether the engineered features are suitable for a
scientifically defensible ML experiment.

Input
-----
data/processed/inrae/inrae_ml_features_30min.csv

Output
------
reports/inrae_feature_audit.txt
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
    / "inrae_ml_features_30min.csv"
)

REPORT_DIR = PROJECT_ROOT / "reports"

REPORT_FILE = (
    REPORT_DIR
    / "inrae_feature_audit.txt"
)


# =====================================================================
# CONFIGURATION
# =====================================================================

TARGET_COLUMN = "periode"

GROUP_COLUMN = "porc"

TIME_COLUMN = "window_start"


# These are the features that should have been created by the
# feature-engineering script.
EXPECTED_FEATURES = [
    "T_IM_mean",
    "T_IM_std",
    "T_IM_min",
    "T_IM_max",
    "T_IM_median",
    "T_IM_q25",
    "T_IM_q75",
    "T_IM_range",
    "T_mean",
    "T_std",
    "T_min",
    "T_max",
    "T_median",
    "T_q25",
    "T_q75",
    "T_range",
    "age_mean",
    "ADFI_mean",
    "ADFI_std",
    "stage_mean",
    "T_IM_change",
    "T_IM_abs_change",
    "T_IM_change_direction",
    "T_IM_rolling_mean_3",
    "T_IM_rolling_std_3",
]


# Environmental temperature is known to be part of the experimental
# heat-stress manipulation.
#
# It is therefore audited separately rather than automatically
# accepted as a physiologically meaningful predictor.
SCHEDULE_PROXY_FEATURES = [
    "T_mean",
    "T_min",
    "T_max",
    "T_median",
    "T_q25",
    "T_q75",
    "T_range",
]


# Features that represent internal/core temperature.
CORE_TEMPERATURE_FEATURES = [
    "T_IM_mean",
    "T_IM_std",
    "T_IM_min",
    "T_IM_max",
    "T_IM_median",
    "T_IM_q25",
    "T_IM_q75",
    "T_IM_range",
    "T_IM_change",
    "T_IM_abs_change",
    "T_IM_change_direction",
    "T_IM_rolling_mean_3",
    "T_IM_rolling_std_3",
]


# Potentially confounded biological/context variables.
CONTEXT_FEATURES = [
    "age_mean",
    "ADFI_mean",
    "ADFI_std",
    "stage_mean",
]


# =====================================================================
# HELPERS
# =====================================================================

def print_section(title: str):
    print()
    print("=" * 78)
    print(title)
    print("=" * 78)


def numeric_summary(
    df: pd.DataFrame,
    columns,
) -> pd.DataFrame:

    rows = []

    for column in columns:

        if column not in df.columns:
            continue

        values = pd.to_numeric(
            df[column],
            errors="coerce",
        )

        rows.append(
            {
                "feature": column,
                "count": int(values.notna().sum()),
                "missing": int(values.isna().sum()),
                "missing_pct": (
                    values.isna().mean() * 100
                ),
                "mean": values.mean(),
                "std": values.std(),
                "min": values.min(),
                "median": values.median(),
                "max": values.max(),
                "unique": values.nunique(
                    dropna=True
                ),
            }
        )

    return pd.DataFrame(rows)


def class_feature_summary(
    df: pd.DataFrame,
    feature_columns,
) -> pd.DataFrame:

    frames = []

    for target_value, group in df.groupby(
        TARGET_COLUMN,
        dropna=False,
    ):

        summary = (
            group[feature_columns]
            .apply(
                pd.to_numeric,
                errors="coerce",
            )
            .mean()
            .rename(str(target_value))
        )

        frames.append(summary)

    if not frames:
        return pd.DataFrame()

    return pd.concat(
        frames,
        axis=1,
    )


# =====================================================================
# MAIN
# =====================================================================

def main():

    print("=" * 78)
    print("INRAE ENGINEERED FEATURE AUDIT")
    print("=" * 78)

    print(
        f"\nInput:\n{INPUT_FILE}"
    )

    # -----------------------------------------------------------------
    # LOAD
    # -----------------------------------------------------------------

    print_section(
        "[1/12] Loading engineered INRAE dataset"
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
        f"Rows    : {len(df):,}"
    )

    print(
        f"Columns : {len(df.columns):,}"
    )

    # -----------------------------------------------------------------
    # COLUMN VALIDATION
    # -----------------------------------------------------------------

    print_section(
        "[2/12] Validating columns"
    )

    required_columns = [
        GROUP_COLUMN,
        TIME_COLUMN,
        TARGET_COLUMN,
        *EXPECTED_FEATURES,
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
        "All expected columns are present."
    )

    feature_columns = [
        column
        for column in df.columns
        if column not in {
            GROUP_COLUMN,
            TIME_COLUMN,
            TARGET_COLUMN,
        }
    ]

    print(
        f"ML feature columns: "
        f"{len(feature_columns)}"
    )

    # -----------------------------------------------------------------
    # TARGET AUDIT
    # -----------------------------------------------------------------

    print_section(
        "[3/12] Auditing experimental target"
    )

    target_counts = (
        df[TARGET_COLUMN]
        .value_counts(
            dropna=False
        )
    )

    print(
        target_counts.to_string()
    )

    print(
        "\nTarget percentages:"
    )

    target_percentages = (
        df[TARGET_COLUMN]
        .value_counts(
            normalize=True,
            dropna=False,
        )
        * 100
    )

    for target, percentage in target_percentages.items():

        print(
            f"  {target}: "
            f"{percentage:.3f}%"
        )

    # -----------------------------------------------------------------
    # PIG AUDIT
    # -----------------------------------------------------------------

    print_section(
        "[4/12] Auditing pigs and windows"
    )

    unique_pigs = (
        df[GROUP_COLUMN]
        .nunique(
            dropna=True
        )
    )

    print(
        f"Unique pigs: {unique_pigs:,}"
    )

    windows_per_pig = (
        df.groupby(
            GROUP_COLUMN
        )
        .size()
    )

    print(
        "\nWindows per pig:"
    )

    print(
        windows_per_pig.describe()
        .to_string()
    )

    print(
        "\nMinimum windows per pig: "
        f"{windows_per_pig.min():,}"
    )

    print(
        "Maximum windows per pig: "
        f"{windows_per_pig.max():,}"
    )

    # -----------------------------------------------------------------
    # TARGET PER PIG
    # -----------------------------------------------------------------

    print_section(
        "[5/12] Auditing target coverage per pig"
    )

    pig_target_counts = (
        df.groupby(
            GROUP_COLUMN
        )[TARGET_COLUMN]
        .nunique()
    )

    print(
        "Number of pigs by number of target classes observed:"
    )

    print(
        pig_target_counts
        .value_counts()
        .sort_index()
        .to_string()
    )

    print(
        "\nPigs containing each target:"
    )

    pig_target_table = pd.crosstab(
        df[GROUP_COLUMN],
        df[TARGET_COLUMN],
    )

    print(
        pig_target_table.to_string()
    )

    # -----------------------------------------------------------------
    # TIME AUDIT
    # -----------------------------------------------------------------

    print_section(
        "[6/12] Auditing window timestamps"
    )

    timestamps = pd.to_datetime(
        df[TIME_COLUMN],
        errors="coerce",
    )

    invalid_timestamps = int(
        timestamps.isna().sum()
    )

    print(
        f"Invalid window timestamps: "
        f"{invalid_timestamps:,}"
    )

    if timestamps.notna().any():

        print(
            "Earliest window: "
            f"{timestamps.min()}"
        )

        print(
            "Latest window: "
            f"{timestamps.max()}"
        )

    # -----------------------------------------------------------------
    # MISSING VALUES
    # -----------------------------------------------------------------

    print_section(
        "[7/12] Auditing missing feature values"
    )

    missing_summary = numeric_summary(
        df,
        feature_columns,
    )

    missing_summary = (
        missing_summary
        .sort_values(
            "missing",
            ascending=False,
        )
    )

    print(
        missing_summary[
            [
                "feature",
                "count",
                "missing",
                "missing_pct",
            ]
        ]
        .to_string(
            index=False
        )
    )

    total_missing = int(
        df[feature_columns]
        .isna()
        .sum()
        .sum()
    )

    print(
        f"\nTotal missing feature values: "
        f"{total_missing:,}"
    )

    # -----------------------------------------------------------------
    # FEATURE DISTRIBUTIONS
    # -----------------------------------------------------------------

    print_section(
        "[8/12] Auditing feature distributions"
    )

    distribution_summary = numeric_summary(
        df,
        feature_columns,
    )

    print(
        distribution_summary.to_string(
            index=False
        )
    )

    # -----------------------------------------------------------------
    # TARGET VS FEATURES
    # -----------------------------------------------------------------

    print_section(
        "[9/12] Comparing features across experimental periods"
    )

    comparison_features = (
        CORE_TEMPERATURE_FEATURES
        + SCHEDULE_PROXY_FEATURES
        + CONTEXT_FEATURES
    )

    comparison_features = [
        column
        for column in comparison_features
        if column in df.columns
    ]

    class_means = class_feature_summary(
        df,
        comparison_features,
    )

    print(
        class_means.to_string()
    )

    # -----------------------------------------------------------------
    # CORRELATION
    # -----------------------------------------------------------------

    print_section(
        "[10/12] Auditing feature correlations"
    )

    numeric_feature_matrix = (
        df[feature_columns]
        .apply(
            pd.to_numeric,
            errors="coerce",
        )
    )

    correlation = (
        numeric_feature_matrix
        .corr()
    )

    # Find strongest absolute correlations,
    # excluding the diagonal.

    correlation_pairs = []

    columns = correlation.columns.tolist()

    for i in range(len(columns)):

        for j in range(i + 1, len(columns)):

            value = correlation.iloc[
                i,
                j,
            ]

            if pd.isna(value):
                continue

            correlation_pairs.append(
                (
                    columns[i],
                    columns[j],
                    value,
                    abs(value),
                )
            )

    correlation_pairs.sort(
        key=lambda x: x[3],
        reverse=True,
    )

    print(
        "\nTop 20 absolute feature correlations:"
    )

    for (
        feature_a,
        feature_b,
        value,
        absolute_value,
    ) in correlation_pairs[:20]:

        print(
            f"  {feature_a:30s} "
            f"<-> "
            f"{feature_b:30s} "
            f"{value:+.4f}"
        )

    # -----------------------------------------------------------------
    # ENVIRONMENTAL TEMPERATURE AUDIT
    # -----------------------------------------------------------------

    print_section(
        "[11/12] Auditing environmental-temperature proxy risk"
    )

    print(
        "Environmental-temperature features:"
    )

    for feature in SCHEDULE_PROXY_FEATURES:

        if feature not in df.columns:
            continue

        values = pd.to_numeric(
            df[feature],
            errors="coerce",
        )

        print(
            f"\n{feature}"
        )

        print(
            f"  unique values : "
            f"{values.nunique(dropna=True)}"
        )

        print(
            f"  mean          : "
            f"{values.mean():.6f}"
        )

        print(
            f"  std           : "
            f"{values.std():.6f}"
        )

        print(
            f"  min           : "
            f"{values.min():.6f}"
        )

        print(
            f"  max           : "
            f"{values.max():.6f}"
        )

    print(
        "\nEnvironmental temperature by period:"
    )

    if "T_mean" in df.columns:

        environmental_by_period = (
            df.groupby(
                TARGET_COLUMN
            )["T_mean"]
            .agg(
                [
                    "count",
                    "mean",
                    "std",
                    "min",
                    "max",
                ]
            )
        )

        print(
            environmental_by_period.to_string()
        )

    # -----------------------------------------------------------------
    # CORE TEMPERATURE AUDIT
    # -----------------------------------------------------------------

    print(
        "\nCore/internal temperature by period:"
    )

    if "T_IM_mean" in df.columns:

        core_by_period = (
            df.groupby(
                TARGET_COLUMN
            )["T_IM_mean"]
            .agg(
                [
                    "count",
                    "mean",
                    "std",
                    "min",
                    "max",
                ]
            )
        )

        print(
            core_by_period.to_string()
        )

    # -----------------------------------------------------------------
    # BUILD REPORT
    # -----------------------------------------------------------------

    print_section(
        "[12/12] Building audit report"
    )

    report = []

    report.append(
        "INRAE ENGINEERED FEATURE AUDIT\n"
    )

    report.append(
        f"Input file: {INPUT_FILE}\n"
    )

    report.append(
        f"Rows: {len(df):,}\n"
        f"Columns: {len(df.columns):,}\n"
        f"ML features: {len(feature_columns):,}\n"
        f"Unique pigs: {unique_pigs:,}\n"
    )

    report.append(
        "\n" + "=" * 78
        + "\nTARGET DISTRIBUTION\n"
        + "=" * 78
        + "\n"
    )

    report.append(
        target_counts.to_string()
        + "\n\n"
    )

    report.append(
        target_percentages.to_string()
        + "\n"
    )

    report.append(
        "\n" + "=" * 78
        + "\nPIG / WINDOW STRUCTURE\n"
        + "=" * 78
        + "\n"
    )

    report.append(
        windows_per_pig.describe().to_string()
        + "\n\n"
    )

    report.append(
        "Target classes observed per pig:\n"
    )

    report.append(
        pig_target_counts
        .value_counts()
        .sort_index()
        .to_string()
        + "\n"
    )

    report.append(
        "\n" + "=" * 78
        + "\nMISSING FEATURE VALUES\n"
        + "=" * 78
        + "\n"
    )

    report.append(
        missing_summary.to_string(
            index=False
        )
        + "\n"
    )

    report.append(
        f"\nTotal missing feature values: "
        f"{total_missing:,}\n"
    )

    report.append(
        "\n" + "=" * 78
        + "\nFEATURE DISTRIBUTIONS\n"
        + "=" * 78
        + "\n"
    )

    report.append(
        distribution_summary.to_string(
            index=False
        )
        + "\n"
    )

    report.append(
        "\n" + "=" * 78
        + "\nFEATURE MEANS BY EXPERIMENTAL PERIOD\n"
        + "=" * 78
        + "\n"
    )

    report.append(
        class_means.to_string()
        + "\n"
    )

    report.append(
        "\n" + "=" * 78
        + "\nTOP FEATURE CORRELATIONS\n"
        + "=" * 78
        + "\n"
    )

    for (
        feature_a,
        feature_b,
        value,
        absolute_value,
    ) in correlation_pairs[:20]:

        report.append(
            f"{feature_a} <-> "
            f"{feature_b}: "
            f"{value:+.4f}\n"
        )

    report.append(
        "\n" + "=" * 78
        + "\nENVIRONMENTAL TEMPERATURE AUDIT\n"
        + "=" * 78
        + "\n"
    )

    if "T_mean" in df.columns:

        report.append(
            environmental_by_period.to_string()
            + "\n"
        )

    report.append(
        "\n" + "=" * 78
        + "\nCORE TEMPERATURE AUDIT\n"
        + "=" * 78
        + "\n"
    )

    if "T_IM_mean" in df.columns:

        report.append(
            core_by_period.to_string()
            + "\n"
        )

    report.append(
        "\n" + "=" * 78
        + "\nSCIENTIFIC INTERPRETATION\n"
        + "=" * 78
        + "\n"
    )

    report.append(
        """
1. The dataset contains genuine experimental observations and
   therefore does not require synthetic data generation.

2. Pig identity must remain a grouping variable rather than an ML
   predictor.

3. The experimental period must not be renamed into PRISM risk
   categories.

4. Environmental temperature variables require special caution.
   They are part of the thermal-stress experimental manipulation and
   may directly reveal the experimental period.

5. Internal/core temperature (T_IM) is a more scientifically relevant
   physiological signal for investigating the animal's response to
   thermal conditions.

6. A high classification score obtained primarily from environmental
   temperature would not by itself demonstrate that the model has
   learned a transferable physiological response.

7. The final PRISM risk classes must eventually be learned from real
   PRISM farm observations and genuine farm ground truth.

8. Before training, the final ML task should therefore be selected
   based on this audit rather than simply maximizing classification
   accuracy.
"""
    )

    # -----------------------------------------------------------------
    # SAVE
    # -----------------------------------------------------------------

    REPORT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    REPORT_FILE.write_text(
        "\n".join(report),
        encoding="utf-8",
    )

    print(
        f"\nAudit report saved:\n{REPORT_FILE}"
    )

    print()
    print("=" * 78)
    print(
        "INRAE engineered feature audit completed."
    )
    print("=" * 78)


if __name__ == "__main__":
    main()