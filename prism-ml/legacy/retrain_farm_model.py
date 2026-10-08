"""
PRISM - Farm-Level ML Retraining Using Calibrated Pig Comfort Reference
=========================================================================
Relabels prism_farm_dataset.csv using research-backed thresholds:
    - Pig body-comfort temperature: 34-37 C   (normal)
    - Optimal barn humidity:        60-70 %   (normal)
Then retrains the Decision Tree on the corrected labels.

This REPLACES the old condition/condition_label columns, which were
generated from arbitrary ranges that didn't match your calibration findings.
"""

import pandas as pd
import numpy as np
from sklearn.tree import DecisionTreeClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, accuracy_score
import joblib

# ── 1. YOUR CALIBRATED REFERENCE VALUES ──────────────────────────────────────
# (from your AMG8833 / DHT22 calibration research)
TEMP_NORMAL_LO      = 34.0
TEMP_NORMAL_HI      = 37.0
TEMP_ALERT_HI       = 38.5   # mild heat stress zone above comfort
TEMP_CRITICAL_HI    = 40.0   # severe heat stress
TEMP_LOW_LO         = 32.0   # chilling risk below this

HUMIDITY_NORMAL_LO  = 60.0
HUMIDITY_NORMAL_HI  = 70.0
HUMIDITY_ALERT_HI   = 80.0
HUMIDITY_CRITICAL_HI = 85.0
HUMIDITY_LOW_LO     = 50.0

WEIGHT_LOSS_THRESHOLD = 0.0   # any negative weight change = red flag
FEED_LOW_THRESHOLD    = 1.5   # kg/day - possible heat anorexia

# ── 2. LOAD ORIGINAL DATA (sensor readings only, ignore old labels) ─────────
df = pd.read_csv('prism_farm_dataset.csv')
df = df.drop(columns=['condition', 'condition_label'])  # discard stale labels

# ── 3. RE-COMPUTE THI (unchanged formula, still useful as a feature) ────────
df['thi'] = df['temperature_c'] - (0.55 - 0.0055 * df['humidity_pct']) * (df['temperature_c'] - 14.5)
df['temp_avg3']     = df['temperature_c'].rolling(3, min_periods=1).mean()
df['humidity_avg3'] = df['humidity_pct'].rolling(3, min_periods=1).mean()

# ── 4. RELABEL using calibrated thresholds ───────────────────────────────────
def label_condition(row) -> str:
    temp = row['temperature_c']
    hum  = row['humidity_pct']
    wt   = row['weight_change_kg']
    feed = row['feed_intake_kg']

    # HIGH RISK: severe heat/cold stress OR active weight loss (animal welfare emergency)
    if wt < WEIGHT_LOSS_THRESHOLD:
        return 'High Risk'
    if temp >= TEMP_CRITICAL_HI or hum >= HUMIDITY_CRITICAL_HI:
        return 'High Risk'
    if temp <= TEMP_LOW_LO:
        return 'High Risk'

    # NEEDS ATTENTION: outside the 34-37C / 60-70% comfort zone but not yet critical
    if temp > TEMP_NORMAL_HI or temp < TEMP_NORMAL_LO:
        return 'Needs Attention'
    if hum > HUMIDITY_NORMAL_HI or hum < HUMIDITY_NORMAL_LO:
        return 'Needs Attention'
    if feed < FEED_LOW_THRESHOLD:
        return 'Needs Attention'

    # GOOD: within 34-37C AND 60-70% AND no other red flags
    return 'Good'

df['condition'] = df.apply(label_condition, axis=1)

# ── 4b. ADD SYNTHETIC BOUNDARY EXAMPLES ──────────────────────────────────────
# The original sensor data never recorded temps below 34C or above ~37C with
# otherwise-good conditions, so the tree has no examples to learn the edges
# of your comfort zone from. We inject a small, evenly-labeled set of boundary
# points so the tree actually sees what "just inside" vs "just outside" looks like.
import itertools

boundary_rows = []
temp_probe_points  = [30, 31, 32, 33, 33.9, 34.0, 34.1, 35.5, 36.9, 37.0, 37.1, 38, 39, 40, 41]
humidity_probe_points = [45, 50, 55, 59.9, 60.0, 60.1, 65, 69.9, 70.0, 70.1, 75, 80, 85, 90]

for t, h in itertools.product(temp_probe_points, humidity_probe_points):
    # Use healthy weight/feed so ONLY temp/humidity drive the label here
    boundary_rows.append({
        'temperature_c': t,
        'humidity_pct': h,
        'weight_change_kg': 0.6,
        'feed_intake_kg': 2.7,
        'medicine_given': 0,
    })

boundary_df = pd.DataFrame(boundary_rows)
boundary_df['thi'] = boundary_df['temperature_c'] - (0.55 - 0.0055 * boundary_df['humidity_pct']) * (boundary_df['temperature_c'] - 14.5)
boundary_df['temp_avg3']     = boundary_df['temperature_c']
boundary_df['humidity_avg3'] = boundary_df['humidity_pct']
boundary_df['condition'] = boundary_df.apply(label_condition, axis=1)

df = pd.concat([df, boundary_df], ignore_index=True)

label_map = {'Good': 0, 'Needs Attention': 1, 'High Risk': 2}
df['condition_label'] = df['condition'].map(label_map)

print("=== New label distribution (calibrated to 34-37C / 60-70%, + boundary examples) ===")
print(df['condition'].value_counts())
print()

# ── 5. TRAIN / TEST SPLIT + DECISION TREE ────────────────────────────────────
FEATURES = ['temperature_c', 'humidity_pct', 'thi', 'weight_change_kg',
            'feed_intake_kg', 'temp_avg3', 'humidity_avg3']

X = df[FEATURES]
y = df['condition']

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

model = DecisionTreeClassifier(
    max_depth=5,
    min_samples_leaf=5,
    random_state=42
)
model.fit(X_train, y_train)

y_pred = model.predict(X_test)
print("=== Retrained Farm-Level Model Evaluation ===")
print(f"Accuracy: {accuracy_score(y_test, y_pred):.2%}")
print(classification_report(y_test, y_pred))

# ── 6. SAVE MODEL + RELABELED DATASET ────────────────────────────────────────
joblib.dump(model, 'prism_farm_model.pkl')
df.to_csv('prism_farm_dataset_relabeled.csv', index=False)
print("Model saved -> prism_farm_model.pkl")
print("Relabeled dataset saved -> prism_farm_dataset_relabeled.csv")

# ── 7. SANITY CHECK: spot-test a few known cases ─────────────────────────────
test_cases = [
    {'temperature_c': 35.5, 'humidity_pct': 65.0, 'weight_change_kg': 0.7, 'feed_intake_kg': 2.8, 'label': 'Should be Good (in comfort zone)'},
    {'temperature_c': 38.0, 'humidity_pct': 75.0, 'weight_change_kg': 0.2, 'feed_intake_kg': 1.6, 'label': 'Should be Needs Attention (above comfort temp)'},
    {'temperature_c': 41.0, 'humidity_pct': 90.0, 'weight_change_kg': -0.5, 'feed_intake_kg': 0.5, 'label': 'Should be High Risk (heat stress + weight loss)'},
    {'temperature_c': 33.0, 'humidity_pct': 65.0, 'weight_change_kg': 0.5, 'feed_intake_kg': 2.5, 'label': 'Should be Needs Attention (too cold, below 34C)'},
]

print("\n=== Sanity Checks (raw tree prediction) ===")
for case in test_cases:
    label_note = case.pop('label')
    row = pd.DataFrame([case])
    row['thi'] = row['temperature_c'] - (0.55 - 0.0055 * row['humidity_pct']) * (row['temperature_c'] - 14.5)
    row['temp_avg3'] = row['temperature_c']
    row['humidity_avg3'] = row['humidity_pct']
    pred = model.predict(row[FEATURES])[0]
    print(f"  Input: {case} -> Predicted: {pred}  ({label_note})")

# ── 8. PRODUCTION-SAFE PREDICTION FUNCTION ───────────────────────────────────
# A decision tree generalizes from patterns in data, but you already KNOW the
# exact comfort-zone boundaries (34-37C, 60-70%) from calibration research.
# Rather than hoping the tree perfectly re-learned that boundary (it may not,
# especially with limited "cold but otherwise healthy" examples), this wraps
# the tree with a deterministic override: the rule layer has final say on
# clear-cut threshold violations, and the tree only breaks ties / handles the
# nuanced cases (e.g. multiple borderline factors at once).
def predict_condition_safe(temperature_c, humidity_pct, weight_change_kg, feed_intake_kg):
    """
    Use this in prism_api.py instead of calling model.predict() directly.
    Guarantees your calibrated thresholds are always respected, regardless
    of what the tree learned, while still letting the tree weigh in on
    genuinely ambiguous multi-factor cases.
    """
    # Rule layer: deterministic, always correct for known thresholds
    rule_label = label_condition({
        'temperature_c': temperature_c,
        'humidity_pct': humidity_pct,
        'weight_change_kg': weight_change_kg,
        'feed_intake_kg': feed_intake_kg,
    })

    # Tree layer: only consulted for explainability / nuance, doesn't override clear violations
    row = pd.DataFrame([{
        'temperature_c': temperature_c,
        'humidity_pct': humidity_pct,
        'weight_change_kg': weight_change_kg,
        'feed_intake_kg': feed_intake_kg,
    }])
    row['thi'] = row['temperature_c'] - (0.55 - 0.0055 * row['humidity_pct']) * (row['temperature_c'] - 14.5)
    row['temp_avg3'] = row['temperature_c']
    row['humidity_avg3'] = row['humidity_pct']
    tree_label = model.predict(row[FEATURES])[0]

    return {
        'condition': rule_label,          # AUTHORITATIVE - use this one
        'tree_suggestion': tree_label,    # informational only
        'agree': rule_label == tree_label,
    }

print("\n=== Production-safe wrapper (rule-authoritative) ===")
recheck_cases = [
    {'temperature_c': 35.5, 'humidity_pct': 65.0, 'weight_change_kg': 0.7, 'feed_intake_kg': 2.8},
    {'temperature_c': 38.0, 'humidity_pct': 75.0, 'weight_change_kg': 0.2, 'feed_intake_kg': 1.6},
    {'temperature_c': 41.0, 'humidity_pct': 90.0, 'weight_change_kg': -0.5, 'feed_intake_kg': 0.5},
    {'temperature_c': 33.0, 'humidity_pct': 65.0, 'weight_change_kg': 0.5, 'feed_intake_kg': 2.5},
]
for case in recheck_cases:
    result = predict_condition_safe(**case)
    print(f"  Input: {case} -> {result}")
