from pathlib import Path
import pandas as pd


# ============================================================
# PATHS
# ============================================================

PROJECT_ROOT = Path(__file__).resolve().parents[2]

RAW_DIR = PROJECT_ROOT / "data" / "raw" / "hotpig" / "series"
OUTPUT_FILE = (
    PROJECT_ROOT
    / "data"
    / "processed"
    / "hotpig"
    / "hotpig_processed.csv"
)


# ============================================================
# PROCESS HOTPIG DATA
# ============================================================

def main():
    print("=" * 80)
    print("HOTPIG DATA PROCESSOR")
    print("=" * 80)

    # --------------------------------------------------------
    # Check input directory
    # --------------------------------------------------------

    if not RAW_DIR.exists():
        raise FileNotFoundError(
            f"HotPig raw data directory not found:\n{RAW_DIR}"
        )

    csv_files = sorted(RAW_DIR.glob("*.csv"))

    if not csv_files:
        raise FileNotFoundError(
            f"No CSV files found in:\n{RAW_DIR}"
        )

    print(f"\nFound {len(csv_files)} CSV files.")

    processed_frames = []

    # --------------------------------------------------------
    # Process each pig file
    # --------------------------------------------------------

    for file in csv_files:

        print(f"\nProcessing: {file.name}")

        df = pd.read_csv(file)

        print(f"  Original rows: {len(df):,}")

        # ----------------------------------------------------
        # The original HotPig timestamp column is called
        # "Unnamed: 0".
        #
        # It is actually the observation timestamp.
        # Rename it to datetime.
        # ----------------------------------------------------

        if "Unnamed: 0" in df.columns:
            df = df.rename(
                columns={
                    "Unnamed: 0": "datetime"
                }
            )

        # ----------------------------------------------------
        # Make sure datetime exists
        # ----------------------------------------------------

        if "datetime" not in df.columns:
            raise ValueError(
                f"'datetime' column not found in {file.name}"
            )

        # ----------------------------------------------------
        # Convert timestamp to actual datetime
        #
        # Invalid values become NaT.
        # We do NOT invent replacement timestamps.
        # ----------------------------------------------------

        df["datetime"] = pd.to_datetime(
            df["datetime"],
            errors="coerce"
        )

        # ----------------------------------------------------
        # Add pig ID from filename
        #
        # Example:
        # P1.csv -> P1
        # P2.csv -> P2
        # ----------------------------------------------------

        pig_id = file.stem

        df["pig_id"] = pig_id

        # ----------------------------------------------------
        # Add source dataset identifier
        # ----------------------------------------------------

        df["source_dataset"] = "HotPig"

        # ----------------------------------------------------
        # Convert numeric behavioral columns
        #
        # We only convert existing columns.
        # Missing values remain missing.
        # ----------------------------------------------------

        numeric_columns = [
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
        ]

        for column in numeric_columns:
            if column in df.columns:
                df[column] = pd.to_numeric(
                    df[column],
                    errors="coerce"
                )

        # ----------------------------------------------------
        # Keep original condition values.
        #
        # IMPORTANT:
        # We do NOT convert:
        #
        # TN -> GOOD
        # HS -> HIGH_RISK
        #
        # The original experimental labels are preserved.
        # ----------------------------------------------------

        # ----------------------------------------------------
        # Store processed dataframe
        # ----------------------------------------------------

        processed_frames.append(df)

    # --------------------------------------------------------
    # Combine all pig files
    # --------------------------------------------------------

    print("\nCombining all HotPig files...")

    combined_df = pd.concat(
        processed_frames,
        ignore_index=True
    )

    # --------------------------------------------------------
    # Create output directory if necessary
    # --------------------------------------------------------

    OUTPUT_FILE.parent.mkdir(
        parents=True,
        exist_ok=True
    )

    # --------------------------------------------------------
    # Save processed dataset
    # --------------------------------------------------------

    combined_df.to_csv(
        OUTPUT_FILE,
        index=False
    )

    # --------------------------------------------------------
    # Summary
    # --------------------------------------------------------

    print("\n" + "=" * 80)
    print("HOTPIG PROCESSING COMPLETE")
    print("=" * 80)

    print(f"Rows: {len(combined_df):,}")
    print(f"Columns: {len(combined_df.columns)}")
    print(f"Pigs: {combined_df['pig_id'].nunique()}")

    if "conditions" in combined_df.columns:
        print("\nExperimental conditions:")
        print(
            combined_df["conditions"]
            .value_counts(dropna=False)
        )

    datetime_missing = combined_df["datetime"].isna().sum()

    print(
        f"\nInvalid/missing datetime values: "
        f"{datetime_missing:,}"
    )

    print(f"\nSaved to:")
    print(OUTPUT_FILE)


# ============================================================
# ENTRY POINT
# ============================================================

if __name__ == "__main__":
    main()