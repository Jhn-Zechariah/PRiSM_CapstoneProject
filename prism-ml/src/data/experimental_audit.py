from pathlib import Path
import pandas as pd


# ============================================================
# PROJECT PATHS
# ============================================================

PROJECT_ROOT = Path(__file__).resolve().parents[2]

DATA_DIR = PROJECT_ROOT / "data" / "processed"

HOTPIG_FILE = (
    DATA_DIR
    / "hotpig"
    / "hotpig_processed.csv"
)

INRAE_FILE = (
    DATA_DIR
    / "inrae"
    / "inrae_processed.csv"
)

BEHAVIOR_FILE = (
    DATA_DIR
    / "behavior_heat_tolerance"
    / "behavior_heat_tolerance_processed.csv"
)


# ============================================================
# DISPLAY HELPERS
# ============================================================

def print_header(title):
    print("\n" + "=" * 80)
    print(title)
    print("=" * 80)


def print_subheader(title):
    print("\n" + "-" * 80)
    print(title)
    print("-" * 80)


# ============================================================
# HOTPIG AUDIT
# ============================================================

def audit_hotpig():
    print_header("HOTPIG EXPERIMENTAL DESIGN AUDIT")

    if not HOTPIG_FILE.exists():
        raise FileNotFoundError(
            f"HotPig processed file not found:\n{HOTPIG_FILE}"
        )

    print(f"\nReading:")
    print(HOTPIG_FILE)

    df = pd.read_csv(HOTPIG_FILE)

    print(f"\nRows: {len(df):,}")
    print(f"Columns: {len(df.columns)}")

    # --------------------------------------------------------
    # Basic structure
    # --------------------------------------------------------

    print_subheader("1. Experimental Conditions")

    if "conditions" not in df.columns:
        print("WARNING: 'conditions' column not found.")
    else:
        print(
            df["conditions"]
            .value_counts(dropna=False)
            .to_string()
        )

    # --------------------------------------------------------
    # Pig participation
    # --------------------------------------------------------

    print_subheader("2. Number of Pigs")

    if "pig_id" in df.columns:
        print(
            f"Unique pigs: "
            f"{df['pig_id'].nunique()}"
        )

    # --------------------------------------------------------
    # Conditions experienced by each pig
    # --------------------------------------------------------

    print_subheader(
        "3. Experimental Conditions Experienced by Each Pig"
    )

    if "pig_id" in df.columns and "conditions" in df.columns:

        pig_condition_table = pd.crosstab(
            df["pig_id"],
            df["conditions"],
            dropna=False
        )

        print(pig_condition_table.to_string())

        print(
            "\nNumber of experimental conditions per pig:"
        )

        condition_count = (
            pig_condition_table
            .gt(0)
            .sum(axis=1)
        )

        print(
            condition_count
            .value_counts()
            .sort_index()
            .to_string()
        )

    # --------------------------------------------------------
    # Time range
    # --------------------------------------------------------

    print_subheader("4. Time Range")

    if "datetime" in df.columns:

        datetime = pd.to_datetime(
            df["datetime"],
            errors="coerce"
        )

        print(
            f"Earliest timestamp: "
            f"{datetime.min()}"
        )

        print(
            f"Latest timestamp: "
            f"{datetime.max()}"
        )

        print(
            f"Invalid timestamps: "
            f"{datetime.isna().sum():,}"
        )

    # --------------------------------------------------------
    # Time range by condition
    # --------------------------------------------------------

    print_subheader(
        "5. Time Range by Experimental Condition"
    )

    if (
        "datetime" in df.columns
        and "conditions" in df.columns
    ):

        df["_datetime"] = pd.to_datetime(
            df["datetime"],
            errors="coerce"
        )

        condition_time = (
            df.groupby("conditions", dropna=False)["_datetime"]
            .agg(["min", "max", "count"])
        )

        print(condition_time.to_string())

        df.drop(columns=["_datetime"], inplace=True)

    # --------------------------------------------------------
    # Condition transitions
    # --------------------------------------------------------

    print_subheader(
        "6. Experimental Condition Transitions"
    )

    if (
        "pig_id" in df.columns
        and "datetime" in df.columns
        and "conditions" in df.columns
    ):

        temp = df[
            ["pig_id", "datetime", "conditions"]
        ].copy()

        temp["datetime"] = pd.to_datetime(
            temp["datetime"],
            errors="coerce"
        )

        temp = temp.sort_values(
            ["pig_id", "datetime"]
        )

        temp["previous_condition"] = (
            temp.groupby("pig_id")["conditions"]
            .shift(1)
        )

        transitions = temp[
            (
                temp["conditions"]
                != temp["previous_condition"]
            )
            & temp["previous_condition"].notna()
            & temp["conditions"].notna()
        ]

        print(
            f"Total condition transitions: "
            f"{len(transitions):,}"
        )

        if len(transitions) > 0:

            transition_counts = (
                transitions
                .groupby(
                    [
                        "previous_condition",
                        "conditions"
                    ]
                )
                .size()
                .sort_values(ascending=False)
            )

            print("\nTransition counts:")

            print(
                transition_counts.to_string()
            )

    # --------------------------------------------------------
    # Behavioral features by condition
    # --------------------------------------------------------

    print_subheader(
        "7. Behavioral Measurements by Condition"
    )

    behavioral_columns = [
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

    available_behavioral = [
        column
        for column in behavioral_columns
        if column in df.columns
    ]

    if available_behavioral and "conditions" in df.columns:

        condition_means = (
            df.groupby("conditions", dropna=False)[
                available_behavioral
            ]
            .mean(numeric_only=True)
        )

        print(
            condition_means.to_string()
        )

    # --------------------------------------------------------
    # Missingness by condition
    # --------------------------------------------------------

    print_subheader(
        "8. Missing Values by Condition"
    )

    if "conditions" in df.columns:

        missing_by_condition = (
            df.groupby("conditions", dropna=False)
            .apply(
                lambda group: group.isna().sum(),
                include_groups=False
            )
        )

        print(
            missing_by_condition.to_string()
        )

    # --------------------------------------------------------
    # Rows per pig
    # --------------------------------------------------------

    print_subheader(
        "9. Number of Observations per Pig"
    )

    if "pig_id" in df.columns:

        observations_per_pig = (
            df["pig_id"]
            .value_counts()
            .sort_index()
        )

        print(
            observations_per_pig.to_string()
        )


# ============================================================
# INRAE AUDIT
# ============================================================

def audit_inrae():
    print_header("INRAE EXPERIMENTAL DESIGN AUDIT")

    if not INRAE_FILE.exists():
        raise FileNotFoundError(
            f"INRAE processed file not found:\n{INRAE_FILE}"
        )

    print(f"\nReading:")
    print(INRAE_FILE)

    df = pd.read_csv(INRAE_FILE)

    print(f"\nRows: {len(df):,}")
    print(f"Columns: {len(df.columns)}")

    # --------------------------------------------------------
    # Number of pigs
    # --------------------------------------------------------

    print_subheader("1. Number of Pigs")

    if "porc" in df.columns:

        print(
            f"Unique pigs: "
            f"{df['porc'].nunique()}"
        )

    # --------------------------------------------------------
    # Experimental periods
    # --------------------------------------------------------

    print_subheader(
        "2. Experimental Periods"
    )

    if "periode" in df.columns:

        print(
            df["periode"]
            .value_counts(dropna=False)
            .to_string()
        )

    # --------------------------------------------------------
    # Challenge IDs
    # --------------------------------------------------------

    print_subheader(
        "3. Experimental Challenges"
    )

    if "id_challenge" in df.columns:

        print(
            f"Unique challenge IDs: "
            f"{df['id_challenge'].nunique(dropna=True)}"
        )

        print("\nChallenge distribution:")

        print(
            df["id_challenge"]
            .value_counts(dropna=False)
            .head(30)
            .to_string()
        )

    # --------------------------------------------------------
    # Period per pig
    # --------------------------------------------------------

    print_subheader(
        "4. Experimental Periods Experienced by Each Pig"
    )

    if "porc" in df.columns and "periode" in df.columns:

        pig_period_table = pd.crosstab(
            df["porc"],
            df["periode"],
            dropna=False
        )

        print(
            pig_period_table.to_string()
        )

        period_count = (
            pig_period_table
            .gt(0)
            .sum(axis=1)
        )

        print(
            "\nNumber of experimental periods per pig:"
        )

        print(
            period_count
            .value_counts()
            .sort_index()
            .to_string()
        )

    # --------------------------------------------------------
    # Time range
    # --------------------------------------------------------

    print_subheader(
        "5. Time Range"
    )

    if "datetime" in df.columns:

        datetime = pd.to_datetime(
            df["datetime"],
            errors="coerce"
        )

        print(
            f"Earliest timestamp: "
            f"{datetime.min()}"
        )

        print(
            f"Latest timestamp: "
            f"{datetime.max()}"
        )

        print(
            f"Invalid timestamps: "
            f"{datetime.isna().sum():,}"
        )

    # --------------------------------------------------------
    # Temperature distributions
    # --------------------------------------------------------

    print_subheader(
        "6. Core and Environmental Temperature"
    )

    temperature_columns = [
        "T_IM",
        "T",
    ]

    available_temperature = [
        column
        for column in temperature_columns
        if column in df.columns
    ]

    if available_temperature:

        print(
            df[available_temperature]
            .describe()
            .to_string()
        )

    # --------------------------------------------------------
    # Temperature by period
    # --------------------------------------------------------

    print_subheader(
        "7. Temperature by Experimental Period"
    )

    if "periode" in df.columns:

        available_temperature = [
            column
            for column in [
                "T_IM",
                "T",
            ]
            if column in df.columns
        ]

        if available_temperature:

            period_temperature = (
                df.groupby("periode", dropna=False)[
                    available_temperature
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
                period_temperature.to_string()
            )

    # --------------------------------------------------------
    # ADFI
    # --------------------------------------------------------

    print_subheader(
        "8. Feed Intake (ADFI)"
    )

    if "ADFI" in df.columns:

        print(
            df["ADFI"]
            .describe()
            .to_string()
        )

    # --------------------------------------------------------
    # Missingness by period
    # --------------------------------------------------------

    print_subheader(
        "9. Missing Values by Experimental Period"
    )

    if "periode" in df.columns:

        missing_by_period = (
            df.groupby("periode", dropna=False)
            .apply(
                lambda group: group.isna().sum(),
                include_groups=False
            )
        )

        print(
            missing_by_period.to_string()
        )

    # --------------------------------------------------------
    # Observations per pig
    # --------------------------------------------------------

    print_subheader(
        "10. Number of Observations per Pig"
    )

    if "porc" in df.columns:

        observations_per_pig = (
            df["porc"]
            .value_counts()
            .sort_index()
        )

        print(
            observations_per_pig.to_string()
        )


# ============================================================
# BEHAVIOR-HEATTOLERANCE AUDIT
# ============================================================

def audit_behavior_heat_tolerance():
    print_header(
        "BEHAVIOR-HEATTOLERANCE EXPERIMENTAL DESIGN AUDIT"
    )

    if not BEHAVIOR_FILE.exists():
        raise FileNotFoundError(
            "Behavior-HeatTolerance processed file "
            f"not found:\n{BEHAVIOR_FILE}"
        )

    print(f"\nReading:")
    print(BEHAVIOR_FILE)

    df = pd.read_csv(BEHAVIOR_FILE)

    print(f"\nRows: {len(df):,}")
    print(f"Columns: {len(df.columns)}")

    # --------------------------------------------------------
    # Animals
    # --------------------------------------------------------

    print_subheader("1. Number of Animals")

    if "anim" in df.columns:

        print(
            f"Unique animals: "
            f"{df['anim'].nunique()}"
        )

    # --------------------------------------------------------
    # Conditions
    # --------------------------------------------------------

    print_subheader(
        "2. Experimental Conditions"
    )

    if "condition" in df.columns:

        print(
            df["condition"]
            .value_counts(dropna=False)
            .to_string()
        )

    # --------------------------------------------------------
    # Conditions per animal
    # --------------------------------------------------------

    print_subheader(
        "3. Experimental Conditions Experienced by Each Animal"
    )

    if (
        "anim" in df.columns
        and "condition" in df.columns
    ):

        animal_condition_table = pd.crosstab(
            df["anim"],
            df["condition"],
            dropna=False
        )

        print(
            animal_condition_table.to_string()
        )

        condition_count = (
            animal_condition_table
            .gt(0)
            .sum(axis=1)
        )

        print(
            "\nNumber of experimental conditions per animal:"
        )

        print(
            condition_count
            .value_counts()
            .sort_index()
            .to_string()
        )

    # --------------------------------------------------------
    # Date range
    # --------------------------------------------------------

    print_subheader(
        "4. Time Range"
    )

    if "date" in df.columns:

        date = pd.to_datetime(
            df["date"],
            errors="coerce"
        )

        print(
            f"Earliest date: "
            f"{date.min()}"
        )

        print(
            f"Latest date: "
            f"{date.max()}"
        )

        print(
            f"Invalid dates: "
            f"{date.isna().sum():,}"
        )

    # --------------------------------------------------------
    # Posture
    # --------------------------------------------------------

    print_subheader(
        "5. Posture Distribution"
    )

    if "posture" in df.columns:

        print(
            df["posture"]
            .value_counts(dropna=False)
            .to_string()
        )

    # --------------------------------------------------------
    # Posture by condition
    # --------------------------------------------------------

    print_subheader(
        "6. Posture by Experimental Condition"
    )

    if (
        "posture" in df.columns
        and "condition" in df.columns
    ):

        posture_condition = pd.crosstab(
            df["condition"],
            df["posture"],
            normalize="index"
        ) * 100

        print(
            posture_condition.round(2).to_string()
        )

    # --------------------------------------------------------
    # Temperature statistics
    # --------------------------------------------------------

    print_subheader(
        "7. Temperature Measurements"
    )

    temperature_columns = [
        "muscle_temp",
        "ambient_temp",
    ]

    available_temperature = [
        column
        for column in temperature_columns
        if column in df.columns
    ]

    if available_temperature:

        print(
            df[available_temperature]
            .describe()
            .to_string()
        )

    # --------------------------------------------------------
    # Temperature by condition
    # --------------------------------------------------------

    print_subheader(
        "8. Temperature by Experimental Condition"
    )

    if "condition" in df.columns:

        available_temperature = [
            column
            for column in [
                "muscle_temp",
                "ambient_temp",
            ]
            if column in df.columns
        ]

        if available_temperature:

            condition_temperature = (
                df.groupby(
                    "condition",
                    dropna=False
                )[available_temperature]
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
                condition_temperature.to_string()
            )

    # --------------------------------------------------------
    # ADG and feed efficiency
    # --------------------------------------------------------

    print_subheader(
        "9. Growth and Feed Efficiency"
    )

    growth_columns = [
        "adg",
        "feed_efficiency",
    ]

    available_growth = [
        column
        for column in growth_columns
        if column in df.columns
    ]

    if available_growth:

        print(
            df[available_growth]
            .describe()
            .to_string()
        )

    # --------------------------------------------------------
    # Growth by condition
    # --------------------------------------------------------

    print_subheader(
        "10. Growth and Feed Efficiency by Condition"
    )

    if "condition" in df.columns:

        available_growth = [
            column
            for column in [
                "adg",
                "feed_efficiency",
            ]
            if column in df.columns
        ]

        if available_growth:

            condition_growth = (
                df.groupby(
                    "condition",
                    dropna=False
                )[available_growth]
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
                condition_growth.to_string()
            )

    # --------------------------------------------------------
    # Missingness by condition
    # --------------------------------------------------------

    print_subheader(
        "11. Missing Values by Experimental Condition"
    )

    if "condition" in df.columns:

        missing_by_condition = (
            df.groupby(
                "condition",
                dropna=False
            )
            .apply(
                lambda group: group.isna().sum(),
                include_groups=False
            )
        )

        print(
            missing_by_condition.to_string()
        )

    # --------------------------------------------------------
    # Observations per animal
    # --------------------------------------------------------

    print_subheader(
        "12. Number of Observations per Animal"
    )

    if "anim" in df.columns:

        observations_per_animal = (
            df["anim"]
            .value_counts()
            .sort_index()
        )

        print(
            observations_per_animal.to_string()
        )


# ============================================================
# MAIN
# ============================================================

def main():

    print("\n")
    print("#" * 80)
    print("# PRISM ML - EXPERIMENTAL DESIGN AUDIT")
    print("#")
    print("# Purpose:")
    print("#   Understand the genuine experimental structure")
    print("#   before selecting an ML target or training a model.")
    print("#")
    print("# This script DOES NOT:")
    print("#   - modify datasets")
    print("#   - create labels")
    print("#   - create synthetic observations")
    print("#   - merge datasets")
    print("#   - train ML models")
    print("#" * 80)

    audit_hotpig()

    audit_inrae()

    audit_behavior_heat_tolerance()

    print_header(
        "EXPERIMENTAL AUDIT COMPLETE"
    )

    print(
        """
No datasets were modified.
No labels were created.
No synthetic observations were created.
No datasets were merged.
No machine-learning model was trained.

The next step is to use these results to determine:
1. Which dataset should provide the first ML task.
2. What the legitimate target should be.
3. Which features can be used without leakage.
4. How animals should be divided between training and testing.
"""
    )


if __name__ == "__main__":
    main()