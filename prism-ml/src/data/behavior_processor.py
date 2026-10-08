from pathlib import Path
import pandas as pd


# ============================================================
# PATHS
# ============================================================

PROJECT_ROOT = Path(__file__).resolve().parents[2]

RAW_FILE = (
    PROJECT_ROOT
    / "data"
    / "raw"
    / "behavior_heat_tolerance"
    / "Behavior-HeatTolerance.txt"
)

OUTPUT_FILE = (
    PROJECT_ROOT
    / "data"
    / "processed"
    / "behavior_heat_tolerance"
    / "behavior_heat_tolerance_processed.csv"
)


# ============================================================
# PROCESS BEHAVIOR × HEAT TOLERANCE DATA
# ============================================================

def main():

    print("=" * 80)
    print("BEHAVIOR-HEATTOLERANCE DATA PROCESSOR")
    print("=" * 80)

    # --------------------------------------------------------
    # Check input file
    # --------------------------------------------------------

    if not RAW_FILE.exists():
        raise FileNotFoundError(
            f"Raw Behavior-HeatTolerance file not found:\n{RAW_FILE}"
        )

    print(f"\nReading:")
    print(RAW_FILE)

    # --------------------------------------------------------
    # Read the original TXT file.
    #
    # The audit showed that the file is comma-separated.
    #
    # IMPORTANT:
    # .txt is only the file extension.
    # The actual delimiter is comma.
    # --------------------------------------------------------

    df = pd.read_csv(
        RAW_FILE,
        sep=","
    )

    print(f"\nOriginal rows: {len(df):,}")
    print(f"Original columns: {len(df.columns)}")

    # --------------------------------------------------------
    # Expected columns from the real dataset
    # --------------------------------------------------------

    expected_columns = [
        "date",
        "anim",
        "posture",
        "muscle_temp",
        "ambient_temp",
        "condition",
        "adg",
        "feed_efficiency",
    ]

    # --------------------------------------------------------
    # Verify that all expected columns exist
    # --------------------------------------------------------

    missing_columns = [
        column
        for column in expected_columns
        if column not in df.columns
    ]

    if missing_columns:
        raise ValueError(
            "The following expected columns are missing:\n"
            + "\n".join(missing_columns)
        )

    # --------------------------------------------------------
    # Keep only the expected original variables.
    #
    # This prevents accidental extra columns from entering
    # the processed dataset.
    # --------------------------------------------------------

    df = df[expected_columns].copy()

    # --------------------------------------------------------
    # Convert date to actual datetime
    #
    # Invalid dates become NaT.
    # We do NOT invent replacement dates.
    # --------------------------------------------------------

    df["date"] = pd.to_datetime(
        df["date"],
        errors="coerce"
    )

    # --------------------------------------------------------
    # Convert animal ID to numeric
    # --------------------------------------------------------

    df["anim"] = pd.to_numeric(
        df["anim"],
        errors="coerce"
    )

    # --------------------------------------------------------
    # Convert numerical measurements
    #
    # Missing values remain missing.
    # No synthetic values are generated.
    # --------------------------------------------------------

    numeric_columns = [
        "muscle_temp",
        "ambient_temp",
        "adg",
        "feed_efficiency",
    ]

    for column in numeric_columns:
        df[column] = pd.to_numeric(
            df[column],
            errors="coerce"
        )

    # --------------------------------------------------------
    # Add source dataset identifier
    # --------------------------------------------------------

    df["source_dataset"] = "Behavior-HeatTolerance"

    # --------------------------------------------------------
    # IMPORTANT:
    #
    # The original experimental condition is preserved:
    #
    # TN = thermoneutral condition
    # HS = heat stress condition
    #
    # We DO NOT transform these into PRISM labels such as:
    #
    # TN -> GOOD
    # HS -> HIGH_RISK
    #
    # Those PRISM labels require their own ground-truth
    # protocol from the real PRISM farm.
    # --------------------------------------------------------

    # --------------------------------------------------------
    # Create output directory
    # --------------------------------------------------------

    OUTPUT_FILE.parent.mkdir(
        parents=True,
        exist_ok=True
    )

    # --------------------------------------------------------
    # Save processed dataset
    # --------------------------------------------------------

    df.to_csv(
        OUTPUT_FILE,
        index=False
    )

    # --------------------------------------------------------
    # Summary
    # --------------------------------------------------------

    print("\n" + "=" * 80)
    print("BEHAVIOR-HEATTOLERANCE PROCESSING COMPLETE")
    print("=" * 80)

    print(f"Rows: {len(df):,}")
    print(f"Columns: {len(df.columns)}")

    print(f"\nAnimals: {df['anim'].nunique()}")

    print("\nConditions:")
    print(
        df["condition"]
        .value_counts(dropna=False)
    )

    print("\nPostures:")
    print(
        df["posture"]
        .value_counts(dropna=False)
    )

    date_missing = df["date"].isna().sum()

    print(
        f"\nInvalid/missing date values: "
        f"{date_missing:,}"
    )

    print("\nMissing values:")
    print(
        df.isna().sum()
    )

    print(f"\nSaved to:")
    print(OUTPUT_FILE)


# ============================================================
# ENTRY POINT
# ============================================================

if __name__ == "__main__":
    main()