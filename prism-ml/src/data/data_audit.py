from pathlib import Path
import pandas as pd


# =========================================================
# Project paths
# =========================================================

PROJECT_ROOT = Path(__file__).resolve().parents[2]

PROCESSED_DIR = PROJECT_ROOT / "data" / "processed"

DATASETS = {
    "HotPig": PROCESSED_DIR / "hotpig" / "hotpig_processed.csv",
    "INRAE": PROCESSED_DIR / "inrae" / "inrae_processed.csv",
    "Behavior-HeatTolerance": (
        PROCESSED_DIR
        / "behavior_heat_tolerance"
        / "behavior_heat_tolerance_processed.csv"
    ),
}


# =========================================================
# Helper functions
# =========================================================

def print_separator():
    print("\n" + "=" * 80)


def audit_dataset(name, file_path):
    print_separator()
    print(f"DATASET: {name}")
    print(f"FILE: {file_path}")

    if not file_path.exists():
        print("ERROR: File does not exist.")
        return

    # Read CSV
    df = pd.read_csv(file_path, low_memory=False)

    print("\n--- BASIC INFORMATION ---")
    print(f"Rows: {len(df):,}")
    print(f"Columns: {len(df.columns)}")

    print("\n--- COLUMN NAMES ---")
    for column in df.columns:
        print(f"  - {column}")

    print("\n--- DATA TYPES ---")
    print(df.dtypes.to_string())

    print("\n--- MISSING VALUES ---")
    missing = df.isna().sum()

    missing_table = pd.DataFrame({
        "missing_count": missing,
        "missing_percent": (missing / len(df) * 100).round(2)
    })

    print(missing_table.to_string())

    print("\n--- UNIQUE VALUES ---")

    for column in df.columns:
        unique_count = df[column].nunique(dropna=True)

        print(f"\n{column}: {unique_count:,} unique values")

        # Only print actual values for low-cardinality columns.
        if unique_count <= 20:
            values = df[column].dropna().unique()
            print("  Values:", values)

    print("\n--- NUMERIC SUMMARY ---")

    numeric_columns = df.select_dtypes(
        include=["number"]
    ).columns

    if len(numeric_columns) > 0:
        print(
            df[numeric_columns]
            .describe()
            .transpose()
            .to_string()
        )
    else:
        print("No numeric columns found.")

    print("\n--- SAMPLE RECORDS ---")
    print(df.head(5).to_string())

    print("\n--- DUPLICATE ROWS ---")
    duplicate_count = df.duplicated().sum()
    print(f"Duplicate rows: {duplicate_count:,}")

    return df


# =========================================================
# Main audit
# =========================================================

def main():
    print("=" * 80)
    print("PRISM REAL-DATA AUDIT")
    print("=" * 80)

    for name, file_path in DATASETS.items():
        audit_dataset(name, file_path)

    print_separator()
    print("AUDIT COMPLETE")
    print_separator()

    print(
        "\nImportant:"
        "\n- No labels were created by this audit."
        "\n- No rows were modified."
        "\n- No datasets were merged."
        "\n- No synthetic observations were created."
    )


if __name__ == "__main__":
    main()