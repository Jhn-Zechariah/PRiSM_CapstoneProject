"""
PRISM - Per-Pig Individual Weight Status ML
Decision Tree Classifier: Normal / Underweight / Overweight
"""

import pandas as pd
import numpy as np
from datetime import date
from sklearn.tree import DecisionTreeClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report
import joblib
import os

# ─────────────────────────────────────────────────────────────────────────────
# 1. GROWTH STAGE STANDARDS
#    Based on commercial swine benchmarks (Landrace x Yorkshire crossbreds)
#    Common in Philippine commercial pig farming
# ─────────────────────────────────────────────────────────────────────────────
GROWTH_STAGES = {
    'piglet': {
        'age_range': (0, 21),
        'weight_range_kg': (1.0, 6.5),
        'adg_target_kg': 0.25,
        'description': 'Birth to weaning',
    },
    'nursery': {
        'age_range': (22, 70),
        'weight_range_kg': (6.5, 25.0),
        'adg_target_kg': 0.38,
        'description': 'Post-weaning to starter',
    },
    'grower': {
        'age_range': (71, 120),
        'weight_range_kg': (25.0, 60.0),
        'adg_target_kg': 0.65,
        'description': 'Grower phase',
    },
    'finisher': {
        'age_range': (121, 170),
        'weight_range_kg': (60.0, 110.0),
        'adg_target_kg': 0.80,
        'description': 'Finisher phase — approaching market weight',
    },
}

NORMAL_DEVIATION_PCT  =  15.0
UNDERWEIGHT_THRESHOLD = -15.0
OVERWEIGHT_THRESHOLD  =  15.0

# ─────────────────────────────────────────────────────────────────────────────
# 2. UTILITY FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────
def get_growth_stage(age_days: int) -> str:
    for stage, data in GROWTH_STAGES.items():
        lo, hi = data['age_range']
        if lo <= age_days <= hi:
            return stage
    return 'market_ready'


def compute_pig_features(pig: dict) -> dict:
    """
    pig = {
        'pig_id':         'PIG-001',
        'birth_date':     '2025-01-01',   # ISO format YYYY-MM-DD
        'current_weight': 45.0,            # kg
        'birth_weight':   1.4,             # kg
    }
    """
    birth    = date.fromisoformat(pig['birth_date'])
    age_days = max((date.today() - birth).days, 1)
    stage    = get_growth_stage(age_days)
    std      = GROWTH_STAGES.get(stage)

    adg = (pig['current_weight'] - pig['birth_weight']) / age_days

    if std:
        lo, hi       = std['weight_range_kg']
        target_mid   = (lo + hi) / 2
        weight_dev   = ((pig['current_weight'] - target_mid) / target_mid) * 100
        adg_dev      = ((adg - std['adg_target_kg']) / std['adg_target_kg']) * 100
        exp_lo, exp_hi = lo, hi
    else:
        target_mid   = 110.0
        weight_dev   = 0.0
        adg_dev      = 0.0
        exp_lo, exp_hi = 100.0, 120.0

    return {
        'pig_id':               pig['pig_id'],
        'age_days':             age_days,
        'stage':                stage,
        'current_weight':       pig['current_weight'],
        'birth_weight':         pig['birth_weight'],
        'adg':                  round(adg, 4),
        'weight_deviation_pct': round(weight_dev, 2),
        'adg_deviation_pct':    round(adg_dev, 2),
        'expected_weight_lo':   exp_lo,
        'expected_weight_hi':   exp_hi,
        'target_mid':           target_mid,
        'std':                  std,
    }

# ─────────────────────────────────────────────────────────────────────────────
# 3. RULE-BASED LABELING (for training data generation)
# ─────────────────────────────────────────────────────────────────────────────
def label_pig_weight(row) -> str:
    dev = row['weight_deviation_pct']
    if dev < UNDERWEIGHT_THRESHOLD:
        return 'Underweight'
    elif dev > OVERWEIGHT_THRESHOLD:
        return 'Overweight'
    return 'Normal'

# ─────────────────────────────────────────────────────────────────────────────
# 4. TRAIN MODEL
# ─────────────────────────────────────────────────────────────────────────────
FEATURES = [
    'age_days', 'current_weight', 'birth_weight',
    'adg', 'weight_deviation_pct', 'adg_deviation_pct',
]

def train_pig_weight_model(
    csv_path: str,
    model_save_path: str = 'prism_pig_weight_model.pkl',
):
    df = pd.read_csv(csv_path)
    df['weight_label'] = df.apply(label_pig_weight, axis=1)

    X = df[FEATURES]
    y = df['weight_label']

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y,
    )

    model = DecisionTreeClassifier(
        max_depth=5,
        min_samples_leaf=3,
        class_weight='balanced',
        random_state=42,
    )
    model.fit(X_train, y_train)

    print('=== Per-Pig Weight Classifier ===')
    print(classification_report(y_test, model.predict(X_test)))

    joblib.dump(model, model_save_path)
    print(f'Model saved → {model_save_path}')
    return model

# ─────────────────────────────────────────────────────────────────────────────
# 5. INFERENCE — returns single strings for insight + recommendation
#    ✅ Flutter PigProfileCard expects:
#       result['classification']  → String
#       result['insight']         → String  (NOT a list)
#       result['recommendation']  → String  (NOT a list)
# ─────────────────────────────────────────────────────────────────────────────
def generate_pig_output(
    pig: dict,
    model_path: str = 'prism_pig_weight_model.pkl',
) -> dict:
    """
    pig = {
        'pig_id':         'PIG-042',
        'birth_date':     '2025-01-01',
        'current_weight': 18.0,
        'birth_weight':   1.4,
    }
    """
    model  = joblib.load(model_path)
    feats  = compute_pig_features(pig)
    std    = feats['std'] or {}

    input_df = pd.DataFrame([{f: feats[f] for f in FEATURES}])
    classification = model.predict(input_df)[0]

    age    = feats['age_days']
    stage  = feats['stage']
    weight = feats['current_weight']
    adg    = feats['adg']
    dev    = feats['weight_deviation_pct']
    lo     = feats['expected_weight_lo']
    hi     = feats['expected_weight_hi']
    adg_target = std.get('adg_target_kg', 0) if std else 0

    # ── Build insight and recommendation as single strings ────────────────
    if classification == 'Normal':
        insight = (
            f"Pig is {weight:.1f} kg at {age} days old — within the expected "
            f"range of {lo:.1f}–{hi:.1f} kg for the {stage} stage. "
            f"ADG is {adg:.3f} kg/day, on track with the target of {adg_target:.2f} kg/day."
        )
        recommendation = (
            "Continue current feeding and care routine. "
            "Record next weight at the scheduled weigh-in."
        )

    elif classification == 'Underweight':
        insight = (
            f"Pig is {weight:.1f} kg at {age} days old — {abs(dev):.1f}% below "
            f"the expected midpoint for the {stage} stage ({lo:.1f}–{hi:.1f} kg). "
            f"ADG of {adg:.3f} kg/day is below the target of {adg_target:.2f} kg/day."
        )
        if abs(dev) > 30:
            recommendation = (
                "Weight gap is significant. Review feed quality and quantity. "
                "Check for signs of illness, parasites, or bullying by pen mates. "
                "Consult a veterinarian if no improvement in 7 days."
            )
        else:
            recommendation = (
                "Review feeding schedule and ensure this pig has access to the feeder. "
                "Check for signs of illness: lethargy, diarrhea, or labored breathing. "
                "Consider vitamin supplementation."
            )

    else:  # Overweight
        insight = (
            f"Pig is {weight:.1f} kg at {age} days old — {dev:.1f}% above "
            f"the expected midpoint for the {stage} stage ({lo:.1f}–{hi:.1f} kg). "
            f"Excess weight gain may indicate too-rich a feed or early market readiness."
        )
        if stage == 'finisher' and weight >= 100:
            recommendation = (
                f"Pig has reached {weight:.1f} kg. "
                "Consider scheduling for market soon to optimize carcass quality. "
                "Adjust feed ration to reduce excess fat deposition."
            )
        else:
            recommendation = (
                "Adjust feed ration to prevent excess fat deposition. "
                "Monitor growth rate and review feed composition."
            )

    return {
        'pig_id':         feats['pig_id'],
        'age_days':       age,
        'stage':          stage,
        'current_weight': weight,
        'adg_kg_per_day': adg,
        'expected_range': f"{lo:.1f}–{hi:.1f} kg",
        'deviation_pct':  round(dev, 1),
        # ✅ Single strings — matches Flutter PigProfileCard expectations
        'classification': classification,
        'insight':        insight,
        'recommendation': recommendation,
    }

# ─────────────────────────────────────────────────────────────────────────────
# 6. EXAMPLE USAGE
# ─────────────────────────────────────────────────────────────────────────────
if __name__ == '__main__':
    script_dir = os.path.dirname(os.path.abspath(__file__))
    csv_path   = os.path.join(script_dir, 'dataset_pig_weights.csv')

    model = train_pig_weight_model(csv_path)

    test_pig = {
        'pig_id':         'PIG-007',
        'birth_date':     str(date.today().replace(day=1)),
        'current_weight': 18.0,
        'birth_weight':   1.4,
    }
    result = generate_pig_output(test_pig)
    print('\n=== Sample Pig Output ===')
    for k, v in result.items():
        print(f'{k}: {v}')