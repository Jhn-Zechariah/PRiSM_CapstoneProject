"""
PRISM - Per-Pig Weight ML
Decision Tree Classifier: Normal / Underweight / Overweight
Based on Average Daily Gain (ADG) vs. growth stage standards
"""

import pandas as pd
import numpy as np
from datetime import date
from sklearn.tree import DecisionTreeClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, accuracy_score
import joblib

# ── 1. Growth stage standards (BAI PH + swine production guides) ─────────────
GROWTH_STANDARDS = {
    'starter':  {'age_range': (0,  70),  'weight_range': (1.5, 30),  'adg_target': 0.35},
    'grower':   {'age_range': (71, 105), 'weight_range': (30,  60),  'adg_target': 0.60},
    'finisher': {'age_range': (106,160), 'weight_range': (60,  100), 'adg_target': 0.75},
}

def get_growth_stage(age_days: int) -> str:
    for stage, data in GROWTH_STANDARDS.items():
        if data['age_range'][0] <= age_days <= data['age_range'][1]:
            return stage
    return 'market_ready'

# ── 2. Feature computation from raw pig record ───────────────────────────────
def compute_pig_features(pig: dict) -> dict:
    """
    pig = {
        'pig_id': 'PIG-001',
        'birth_date': '2024-10-01',   # ISO format
        'current_weight': 45.0,        # kg
        'birth_weight': 1.5,           # kg
    }
    """
    birth     = date.fromisoformat(pig['birth_date'])
    age_days  = (date.today() - birth).days
    stage     = get_growth_stage(age_days)
    standard  = GROWTH_STANDARDS.get(stage)

    adg = (pig['current_weight'] - pig['birth_weight']) / age_days if age_days > 0 else 0

    if standard:
        target_mid        = sum(standard['weight_range']) / 2
        weight_dev_pct    = ((pig['current_weight'] - target_mid) / target_mid) * 100
        adg_dev_pct       = ((adg - standard['adg_target']) / standard['adg_target']) * 100
    else:
        target_mid     = 100
        weight_dev_pct = 0
        adg_dev_pct    = 0

    return {
        'pig_id':               pig['pig_id'],
        'age_days':             age_days,
        'stage':                stage,
        'current_weight':       pig['current_weight'],
        'birth_weight':         pig['birth_weight'],
        'adg':                  round(adg, 3),
        'weight_deviation_pct': round(weight_dev_pct, 2),
        'adg_deviation_pct':    round(adg_dev_pct, 2),
        'standard':             standard,
    }

# ── 3. Train model ───────────────────────────────────────────────────────────
df = pd.read_csv('prism_pig_weight_dataset.csv')

FEATURES = ['age_days', 'current_weight_kg', 'adg_kg_per_day',
            'weight_deviation_pct', 'adg_deviation_pct']

X = df[FEATURES]
y = df['weight_label']

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

model = DecisionTreeClassifier(
    max_depth=5,
    min_samples_leaf=3,
    random_state=42
)
model.fit(X_train, y_train)

y_pred = model.predict(X_test)
print("=== Per-Pig Weight Model Evaluation ===")
print(f"Accuracy: {accuracy_score(y_test, y_pred):.2%}")
print(classification_report(y_test, y_pred))

joblib.dump(model, 'prism_pig_weight_model.pkl')
print("Model saved → prism_pig_weight_model.pkl")

# ── 4. Insight & recommendation generator ───────────────────────────────────
def generate_pig_insight(features: dict, classification: str) -> dict:
    stage  = features['stage']
    adg    = features['adg']
    weight = features['current_weight']
    std    = features['standard']
    dev    = features['weight_deviation_pct']

    if classification == 'Normal':
        insight = (
            f"Pig is at {weight:.1f} kg — within the normal range for the {stage} stage. "
            f"ADG is {adg:.3f} kg/day, which is on track."
        )
        recommendation = "Continue current feeding and care routine. Monitor at next weigh-in."

    elif classification == 'Underweight':
        target = std['adg_target'] if std else 'N/A'
        insight = (
            f"Pig is at {weight:.1f} kg — {abs(dev):.1f}% below the expected weight "
            f"for the {stage} stage. ADG of {adg:.3f} kg/day is below the target of "
            f"{target} kg/day."
        )
        recommendation = (
            "Review feeding schedule and check feed quality. "
            "Inspect for signs of illness, parasites, or bullying by pen mates. "
            "Consider vitamin supplementation. Consult a vet if no improvement in 7 days."
        )

    elif classification == 'Overweight':
        insight = (
            f"Pig is at {weight:.1f} kg — {dev:.1f}% above the expected weight "
            f"for the {stage} stage."
        )
        recommendation = (
            "Adjust feed ration to prevent excess fat deposition. "
            "Overweight finishers may have lower carcass quality at market. "
            "Consider earlier market scheduling if weight exceeds 100 kg."
        )
    else:
        insight = "Unable to classify pig weight status."
        recommendation = "Please record accurate birth date and current weight."

    return {
        'pig_id':         features['pig_id'],
        'stage':          stage,
        'age_days':       features['age_days'],
        'current_weight': weight,
        'adg':            adg,
        'classification': classification,
        'insight':        insight,
        'recommendation': recommendation,
    }

# ── 5. Full analysis entry point ─────────────────────────────────────────────
def analyze_pig(pig: dict) -> dict:
    """
    Main function called by PRISM API.
    pig = { 'pig_id', 'birth_date', 'current_weight', 'birth_weight' }
    """
    model   = joblib.load('prism_pig_weight_model.pkl')
    feats   = compute_pig_features(pig)

    input_df = pd.DataFrame([{
        'age_days':             feats['age_days'],
        'current_weight_kg':    feats['current_weight'],
        'adg_kg_per_day':       feats['adg'],
        'weight_deviation_pct': feats['weight_deviation_pct'],
        'adg_deviation_pct':    feats['adg_deviation_pct'],
    }])

    classification = model.predict(input_df)[0]
    return generate_pig_insight(feats, classification)

# ── 6. Example ───────────────────────────────────────────────────────────────
if __name__ == '__main__':
    pig_data = {
        'pig_id':         'PIG-042',
        'birth_date':     '2025-09-01',
        'current_weight': 22.0,
        'birth_weight':   1.5,
    }
    result = analyze_pig(pig_data)
    print("\n=== Sample Pig Analysis ===")
    for k, v in result.items():
        print(f"{k}: {v}")
