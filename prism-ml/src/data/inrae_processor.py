from pathlib import Path
import pandas as pd


# ---------------------------------------------------------
# Paths
# ---------------------------------------------------------

PROJECT_ROOT = Path(__file__).resolve().parents[2]

RAW_FILE = (
    PROJECT_ROOT
    / "data"
    / "raw"
    / "inrae"
    / "File 2 - Core body temperature_raw data.tab"
)

OUTPUT_DIR = (
    PROJECT_ROOT
    / "data"
    / "processed"
    / "inrae"
)

OUTPUT_FILE = OUTPUT_DIR / "inrae_processed.csv"


# ---------------------------------------------------------
# Process INRAE
# ---------------------------------------------------------

def process_inrae():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    if not RAW_FILE.exists():
        raise FileNotFoundError(
            f"Dataset not found: {RAW_FILE}"
        )

    print(f"Reading: {RAW_FILE}")
    print("This may take some time because the dataset is large.")

    # INRAE raw table is tab-delimited.
    df = pd.read_csv(
        RAW_FILE,
        sep="\t",
        low_memory=False
    )

    # Remove completely empty rows.
    df = df.dropna(how="all")

    # Preserve source information.
    df["source_dataset"] = "INRAE"

    # Convert date/time.
    if "datetime" in df.columns:
        df["datetime"] = pd.to_datetime(
            df["datetime"],
            errors="coerce"
        )

    # Convert known numerical variables.
    numeric_columns = [
        "age",
        "T_IM",
        "T",
        "ADFI",
        "temps_relatif_jour",
    ]

    for column in numeric_columns:
        if column in df.columns:
            df[column] = pd.to_numeric(
                df[column],
                errors="coerce"
            )

    # Jour is 100% missing in the raw INRAE data.
    # We do not invent values for it, so remove it
    # from the processed dataset.
    if "Jour" in df.columns:
        df = df.drop(columns=["Jour"])
        
    # Preserve the original experimental condition.
    # We do NOT create PRISM labels here.

    df.to_csv(OUTPUT_FILE, index=False)

    print("\nINRAE processing complete.")
    print(f"Output: {OUTPUT_FILE}")
    print(f"Rows: {len(df):,}")
    print(f"Columns: {len(df.columns)}")

    if "porc" in df.columns:
        print(f"Pigs: {df['porc'].nunique()}")

    if "periode" in df.columns:
        print("\nOriginal experimental periods:")
        print(df["periode"].value_counts(dropna=False))

    print("\nMissing values:")
    print(df.isna().sum())

    print("\nColumns:")
    print(list(df.columns))

    return df


if __name__ == "__main__":
    process_inrae()