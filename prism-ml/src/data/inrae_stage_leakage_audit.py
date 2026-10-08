"""
Audit the INRAE 'stage' variable for experimental-condition leakage.

Purpose
-------
Determine whether stage_mean behaves like a legitimate biological
covariate or whether it is strongly associated with the experimental
thermal-state target.

This script does NOT:
- train a model
- create labels
- modify data
- create synthetic data
- create PRISM risk classes

Input
-----
data/processed/inrae/inrae_ml_features_30min.csv

Output
------
reports/inrae_stage_leakage_audit.txt
"""

from pathlib import Path

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
    / "inrae_stage_leakage_audit.txt"
)


# =====================================================================
# MAIN
# =====================================================================

def main():

    print("=" * 78)
    print("INRAE STAGE LEAKAGE AUDIT")
    print("=" * 78)

    print(
        f"\nInput:\n{INPUT_FILE}"
    )

    if not INPUT_FILE.exists():

        raise FileNotFoundError(
            f"Input file not found:\n{INPUT_FILE}"
        )

    # -----------------------------------------------------------------
    # LOAD
    # -----------------------------------------------------------------

    print(
        "\n[1/8] Loading engineered INRAE dataset..."
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

    required = [
        "porc",
        "window_start",
        "periode",
        "stage_mean",
        "age_mean",
        "ADFI_mean",
    ]

    missing = [
        column
        for column in required
        if column not in df.columns
    ]

    if missing:

        raise ValueError(
            "Missing required columns:\n"
            + "\n".join(
                f"  - {column}"
                for column in missing
            )
        )

    # -----------------------------------------------------------------
    # BASIC STAGE DISTRIBUTION
    # -----------------------------------------------------------------

    print(
        "\n[2/8] Auditing stage distribution..."
    )

    print(
        "\nStage distribution:"
    )

    print(
        df["stage_mean"]
        .describe()
        .to_string()
    )

    print(
        "\nUnique stage_mean values:"
    )

    print(
        df["stage_mean"]
        .nunique(
            dropna=True
        )
    )

    # -----------------------------------------------------------------
    # STAGE BY TARGET
    # -----------------------------------------------------------------

    print(
        "\n[3/8] Comparing stage by experimental period..."
    )

    stage_by_period = (
        df.groupby(
            "periode",
            dropna=False,
        )["stage_mean"]
        .agg(
            [
                "count",
                "mean",
                "std",
                "min",
                "median",
                "max",
            ]
        )
    )

    print(
        "\nStage statistics by period:"
    )

    print(
        stage_by_period.to_string()
    )

    # -----------------------------------------------------------------
    # AGE BY TARGET
    # -----------------------------------------------------------------

    print(
        "\n[4/8] Comparing age by experimental period..."
    )

    age_by_period = (
        df.groupby(
            "periode",
            dropna=False,
        )["age_mean"]
        .agg(
            [
                "count",
                "mean",
                "std",
                "min",
                "median",
                "max",
            ]
        )
    )

    print(
        "\nAge statistics by period:"
    )

    print(
        age_by_period.to_string()
    )

    # -----------------------------------------------------------------
    # STAGE / AGE CORRELATION
    # -----------------------------------------------------------------

    print(
        "\n[5/8] Comparing stage and age..."
    )

    correlation = (
        df[
            [
                "stage_mean",
                "age_mean",
                "ADFI_mean",
            ]
        ]
        .corr()
    )

    print(
        "\nCorrelation matrix:"
    )

    print(
        correlation.to_string()
    )

    # -----------------------------------------------------------------
    # STAGE BY PIG
    # -----------------------------------------------------------------

    print(
        "\n[6/8] Auditing stage behavior within pigs..."
    )

    pig_stage = (
        df.groupby(
            "porc"
        )["stage_mean"]
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
        "\nStage statistics across pigs:"
    )

    print(
        pig_stage.describe()
        .to_string()
    )

    # -----------------------------------------------------------------
    # STAGE / TARGET CROSS TAB
    # -----------------------------------------------------------------

    print(
        "\n[7/8] Auditing stage-target association..."
    )

    stage_target = pd.crosstab(
        df["stage_mean"],
        df["periode"],
        normalize="index",
    )

    print(
        "\nTarget proportions by exact stage_mean:"
    )

    print(
        stage_target.head(50)
        .to_string()
    )

    # -----------------------------------------------------------------
    # REPORT
    # -----------------------------------------------------------------

    print(
        "\n[8/8] Building audit report..."
    )

    report = []

    report.append(
        "INRAE STAGE LEAKAGE AUDIT\n"
    )

    report.append(
        f"Input file: {INPUT_FILE}\n"
        f"Rows: {len(df):,}\n"
        f"Unique pigs: {df['porc'].nunique():,}\n"
    )

    report.append(
        "\n"
        + "=" * 78
        + "\n"
        + "1. STAGE DISTRIBUTION\n"
        + "=" * 78
        + "\n"
    )

    report.append(
        df["stage_mean"]
        .describe()
        .to_string()
        + "\n"
    )

    report.append(
        "\n"
        + "=" * 78
        + "\n"
        + "2. STAGE BY EXPERIMENTAL PERIOD\n"
        + "=" * 78
        + "\n"
    )

    report.append(
        stage_by_period.to_string()
        + "\n"
    )

    report.append(
        "\n"
        + "=" * 78
        + "\n"
        + "3. AGE BY EXPERIMENTAL PERIOD\n"
        + "=" * 78
        + "\n"
    )

    report.append(
        age_by_period.to_string()
        + "\n"
    )

    report.append(
        "\n"
        + "=" * 78
        + "\n"
        + "4. CORRELATION MATRIX\n"
        + "=" * 78
        + "\n"
    )

    report.append(
        correlation.to_string()
        + "\n"
    )

    report.append(
        "\n"
        + "=" * 78
        + "\n"
        + "5. STAGE DISTRIBUTION ACROSS PIGS\n"
        + "=" * 78
        + "\n"
    )

    report.append(
        pig_stage.describe()
        .to_string()
        + "\n"
    )

    report.append(
        "\n"
        + "=" * 78
        + "\n"
        + "6. STAGE / TARGET ASSOCIATION\n"
        + "=" * 78
        + "\n"
    )

    report.append(
        stage_target.to_string()
        + "\n"
    )

    report.append(
        "\n"
        + "=" * 78
        + "\n"
        + "7. INTERPRETATION GUIDANCE\n"
        + "=" * 78
        + "\n"
    )

    report.append(
        """
The stage variable must not automatically be considered a valid
physiological predictor.

If stage_mean closely separates the experimental periods, it may
encode experimental progression, animal development, or another
structured variable associated with the experimental protocol.

A high Random Forest importance for stage_mean therefore does not
automatically demonstrate that stage is a transferable physiological
signal.

The purpose of this audit is to determine whether stage should remain
in the public experimental benchmark.

The final PRISM farm model must only use variables that will actually
be available from the real PRISM farm sensing and data-collection
system.

No PRISM risk labels are created by this audit.
"""
    )

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
        "INRAE stage leakage audit completed."
    )
    print("=" * 78)


if __name__ == "__main__":
    main()