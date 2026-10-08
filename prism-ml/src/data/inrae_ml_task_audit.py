"""
INRAE ML task audit.

Purpose
-------
Audit the genuine INRAE dataset before building an ML model.

This script does NOT:
- create synthetic data
- create synthetic labels
- train a model
- modify the dataset
- create PRISM risk labels
- map INRAE labels to GOOD / NEEDS_ATTENTION / HIGH_RISK

The purpose is to determine which genuine experimental prediction
tasks are scientifically defensible and which variables create
potential leakage.

Input
-----
data/processed/inrae/inrae_processed.csv

Output
------
reports/inrae_ml_task_audit.txt
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

REPORT_DIR = PROJECT_ROOT / "reports"

REPORT_FILE = (
    REPORT_DIR
    / "inrae_ml_task_audit.txt"
)


# =====================================================================
# EXPECTED COLUMNS
# =====================================================================

EXPECTED_COLUMNS = [
    "id_challenge",
    "ordre_challenge",
    "porc",
    "age",
    "stage",
    "datetime",
    "T_IM",
    "T",
    "date_stress",
    "periode",
    "jour_debut_stress",
    "temps_relatif_jour",
    "ADFI",
]


# =====================================================================
# POSSIBLE PREDICTORS
# =====================================================================

CANDIDATE_NUMERIC_FEATURES = [
    "T_IM",
    "T",
    "age",
    "temps_relatif_jour",
    "ADFI",
]

CANDIDATE_CATEGORICAL_FEATURES = [
    "stage",
]


# =====================================================================
# VARIABLES TO EXCLUDE
# =====================================================================

IDENTITY_COLUMNS = [
    "porc",
]

EXPERIMENTAL_IDENTIFIER_COLUMNS = [
    "id_challenge",
    "ordre_challenge",
]

DIRECT_LEAKAGE_COLUMNS = [
    "periode",
]

SCHEDULE_COLUMNS = [
    "datetime",
    "date_stress",
    "jour_debut_stress",
    "temps_relatif_jour",
]

SOURCE_COLUMNS = []


# =====================================================================
# HELPER
# =====================================================================

def section(title: str) -> str:
    return (
        "\n"
        + "=" * 78
        + "\n"
        + title
        + "\n"
        + "=" * 78
        + "\n"
    )


def describe_numeric(
    df: pd.DataFrame,
    column: str,
) -> str:

    if column not in df.columns:
        return (
            f"{column}: COLUMN NOT FOUND\n"
        )

    values = pd.to_numeric(
        df[column],
        errors="coerce",
    )

    return (
        f"{column}\n"
        f"  count   : {values.notna().sum():,}\n"
        f"  missing : {values.isna().sum():,}\n"
        f"  mean    : {values.mean():.6f}\n"
        f"  std     : {values.std():.6f}\n"
        f"  min     : {values.min():.6f}\n"
        f"  median  : {values.median():.6f}\n"
        f"  max     : {values.max():.6f}\n"
    )


# =====================================================================
# MAIN
# =====================================================================

def main():

    print("=" * 78)
    print("INRAE ML TASK AUDIT")
    print("=" * 78)

    print(
        f"\nInput:\n{INPUT_FILE}"
    )

    if not INPUT_FILE.exists():
        raise FileNotFoundError(
            f"INRAE processed dataset not found:\n{INPUT_FILE}"
        )

    # -----------------------------------------------------------------
    # LOAD
    # -----------------------------------------------------------------

    print(
        "\n[1/10] Loading genuine INRAE dataset..."
    )

    df = pd.read_csv(
        INPUT_FILE
    )

    print(
        f"Rows    : {len(df):,}"
    )

    print(
        f"Columns : {len(df.columns):,}"
    )

    # -----------------------------------------------------------------
    # COLUMN CHECK
    # -----------------------------------------------------------------

    print(
        "\n[2/10] Checking columns..."
    )

    missing_expected = [
        column
        for column in EXPECTED_COLUMNS
        if column not in df.columns
    ]

    if missing_expected:
        raise ValueError(
            "Missing expected columns:\n"
            + "\n".join(
                f"  - {column}"
                for column in missing_expected
            )
        )

    print(
        "All expected columns are present."
    )

    # -----------------------------------------------------------------
    # DATETIME
    # -----------------------------------------------------------------

    print(
        "\n[3/10] Auditing timestamps..."
    )

    datetime_values = pd.to_datetime(
        df["datetime"],
        errors="coerce",
    )

    invalid_datetime = int(
        datetime_values.isna().sum()
    )

    print(
        f"Invalid timestamps: "
        f"{invalid_datetime:,}"
    )

    if datetime_values.notna().any():

        print(
            "Earliest valid timestamp: "
            f"{datetime_values.min()}"
        )

        print(
            "Latest valid timestamp: "
            f"{datetime_values.max()}"
        )

    # -----------------------------------------------------------------
    # TARGET / EXPERIMENTAL PERIOD
    # -----------------------------------------------------------------

    print(
        "\n[4/10] Auditing genuine experimental periods..."
    )

    print(
        "\nPeriod counts:"
    )

    print(
        df["periode"]
        .value_counts(dropna=False)
        .to_string()
    )

    period_values = (
        df["periode"]
        .dropna()
        .astype(str)
        .unique()
        .tolist()
    )

    print(
        "\nUnique periods:"
    )

    for value in sorted(period_values):
        print(
            f"  - {value}"
        )

    # -----------------------------------------------------------------
    # PIGS
    # -----------------------------------------------------------------

    print(
        "\n[5/10] Auditing animals and repeated measurements..."
    )

    print(
        f"Unique pigs: "
        f"{df['porc'].nunique(dropna=True):,}"
    )

    print(
        f"Missing pig IDs: "
        f"{df['porc'].isna().sum():,}"
    )

    pig_period_counts = (
        df.dropna(
            subset=[
                "porc",
                "periode",
            ]
        )
        .groupby("porc")["periode"]
        .nunique()
    )

    print(
        "\nNumber of unique experimental periods per pig:"
    )

    print(
        pig_period_counts
        .value_counts()
        .sort_index()
        .to_string()
    )

    # -----------------------------------------------------------------
    # CHALLENGES
    # -----------------------------------------------------------------

    print(
        "\n[6/10] Auditing experimental challenge structure..."
    )

    print(
        f"Unique challenge IDs: "
        f"{df['id_challenge'].nunique(dropna=True):,}"
    )

    print(
        f"Missing challenge IDs: "
        f"{df['id_challenge'].isna().sum():,}"
    )

    print(
        "\nChallenge order distribution:"
    )

    print(
        df["ordre_challenge"]
        .value_counts(dropna=False)
        .sort_index()
        .to_string()
    )

    # -----------------------------------------------------------------
    # NUMERIC VARIABLES
    # -----------------------------------------------------------------

    print(
        "\n[7/10] Auditing numerical variables..."
    )

    numeric_report = []

    for column in CANDIDATE_NUMERIC_FEATURES:

        print(
            "\n"
            + describe_numeric(
                df,
                column,
            )
        )

        numeric_report.append(
            describe_numeric(
                df,
                column,
            )
        )

    # -----------------------------------------------------------------
    # CATEGORICAL VARIABLES
    # -----------------------------------------------------------------

    print(
        "\n[8/10] Auditing categorical variables..."
    )

    categorical_report = []

    for column in CANDIDATE_CATEGORICAL_FEATURES:

        if column not in df.columns:
            continue

        counts = (
            df[column]
            .value_counts(
                dropna=False
            )
        )

        print(
            f"\n{column}:"
        )

        print(
            counts.to_string()
        )

        categorical_report.append(
            f"{column}\n"
            f"{counts.to_string()}\n"
        )

    # -----------------------------------------------------------------
    # PERIOD VS TEMPERATURE
    # -----------------------------------------------------------------

    print(
        "\n[9/10] Checking potential target leakage..."
    )

    period_temperature_report = (
        df.groupby(
            "periode",
            dropna=False,
        )[
            [
                "T_IM",
                "T",
                "age",
                "ADFI",
            ]
        ]
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
        "\nNumeric variables by experimental period:"
    )

    print(
        period_temperature_report.to_string()
    )

    # -----------------------------------------------------------------
    # CORRELATION
    # -----------------------------------------------------------------

    numeric_columns = [
        column
        for column in CANDIDATE_NUMERIC_FEATURES
        if column in df.columns
    ]

    correlation_matrix = (
        df[numeric_columns]
        .apply(
            pd.to_numeric,
            errors="coerce",
        )
        .corr()
    )

    print(
        "\nNumeric correlation matrix:"
    )

    print(
        correlation_matrix.to_string()
    )

    # -----------------------------------------------------------------
    # FINAL TASK RECOMMENDATION
    # -----------------------------------------------------------------

    print(
        "\n[10/10] Building audit report..."
    )

    report_parts = []

    report_parts.append(
        "INRAE ML TASK AUDIT\n"
    )

    report_parts.append(
        f"Input file: {INPUT_FILE}\n"
    )

    report_parts.append(
        f"Rows: {len(df):,}\n"
    )

    report_parts.append(
        f"Columns: {len(df.columns):,}\n"
    )

    report_parts.append(
        section(
            "1. DATASET OVERVIEW"
        )
    )

    report_parts.append(
        f"Rows: {len(df):,}\n"
        f"Columns: {len(df.columns):,}\n"
        f"Unique pigs: "
        f"{df['porc'].nunique(dropna=True):,}\n"
        f"Unique challenges: "
        f"{df['id_challenge'].nunique(dropna=True):,}\n"
    )

    report_parts.append(
        section(
            "2. EXPERIMENTAL TARGET"
        )
    )

    report_parts.append(
        "The genuine experimental variable is 'periode'.\n\n"
    )

    report_parts.append(
        df["periode"]
        .value_counts(dropna=False)
        .to_string()
        + "\n"
    )

    report_parts.append(
        section(
            "3. NUMERICAL FEATURE AUDIT"
        )
    )

    report_parts.extend(
        numeric_report
    )

    report_parts.append(
        section(
            "4. CATEGORICAL FEATURE AUDIT"
        )
    )

    report_parts.extend(
        categorical_report
    )

    report_parts.append(
        section(
            "5. PIG / REPEATED-MEASUREMENT STRUCTURE"
        )
    )

    report_parts.append(
        "Unique periods per pig:\n"
    )

    report_parts.append(
        pig_period_counts
        .value_counts()
        .sort_index()
        .to_string()
        + "\n"
    )

    report_parts.append(
        section(
            "6. CHALLENGE STRUCTURE"
        )
    )

    report_parts.append(
        f"Unique challenge IDs: "
        f"{df['id_challenge'].nunique(dropna=True):,}\n\n"
    )

    report_parts.append(
        "Challenge order distribution:\n"
    )

    report_parts.append(
        df["ordre_challenge"]
        .value_counts(
            dropna=False
        )
        .sort_index()
        .to_string()
        + "\n"
    )

    report_parts.append(
        section(
            "7. PERIOD VS NUMERIC VARIABLES"
        )
    )

    report_parts.append(
        period_temperature_report.to_string()
        + "\n"
    )

    report_parts.append(
        section(
            "8. NUMERIC CORRELATIONS"
        )
    )

    report_parts.append(
        correlation_matrix.to_string()
        + "\n"
    )

    report_parts.append(
        section(
            "9. VARIABLES THAT SHOULD NOT BE USED "
            "AS DIRECT ML PREDICTORS"
        )
    )

    report_parts.append(
        "periode\n"
        "  Reason: this is the experimental target.\n\n"
    )

    report_parts.append(
        "porc\n"
        "  Reason: animal identity can cause memorization and "
        "does not represent a transferable physiological signal.\n\n"
    )

    report_parts.append(
        "id_challenge\n"
        "  Reason: experimental challenge identifier.\n\n"
    )

    report_parts.append(
        "ordre_challenge\n"
        "  Reason: experimental sequence information and potential "
        "schedule leakage.\n\n"
    )

    report_parts.append(
        "datetime\n"
        "  Reason: experimental schedule/time can reveal the "
        "experimental condition rather than physiological response.\n\n"
    )

    report_parts.append(
        "date_stress\n"
        "  Reason: directly encodes stress timing.\n\n"
    )

    report_parts.append(
        "jour_debut_stress\n"
        "  Reason: directly encodes stress timing.\n\n"
    )

    report_parts.append(
        "temps_relatif_jour\n"
        "  Reason: relative experimental timing may encode the "
        "experimental schedule and must be treated cautiously.\n\n"
    )

    report_parts.append(
        section(
            "10. CANDIDATE ML TASK"
        )
    )

    report_parts.append(
        "Candidate genuine experimental task:\n\n"
        "Predict the experimental physiological period using "
        "physiological/environmental measurements.\n\n"
        "Candidate predictors to investigate:\n"
        "  - T_IM\n"
        "  - T\n"
        "  - age\n"
        "  - ADFI\n"
        "  - stage\n\n"
    )

    report_parts.append(
        "Important caution:\n"
        "T may make experimental-period classification nearly "
        "trivial because environmental temperature is directly "
        "related to the heat-stress manipulation. Therefore, "
        "a separate physiological-response task using T_IM should "
        "also be considered rather than relying only on period "
        "classification.\n\n"
    )

    report_parts.append(
        "This audit does NOT establish a final PRISM risk-label "
        "mapping. The INRAE experimental periods must not be "
        "renamed as GOOD, NEEDS_ATTENTION, or HIGH_RISK.\n"
    )

    # -----------------------------------------------------------------
    # SAVE REPORT
    # -----------------------------------------------------------------

    REPORT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    report_text = "\n".join(
        report_parts
    )

    REPORT_FILE.write_text(
        report_text,
        encoding="utf-8",
    )

    print(
        f"\nAudit report saved:\n{REPORT_FILE}"
    )

    print("\n" + "=" * 78)
    print(
        "INRAE ML task audit completed."
    )
    print("=" * 78)


if __name__ == "__main__":
    main()