"""
PRISM - Farm-Level ML (Temperature, Humidity, Weight Change)
Decision Tree Classifier: Good / Needs Attention / High Risk
"""

import pandas as pd
import numpy as np
from sklearn.tree import DecisionTreeClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, accuracy_score
import joblib

# ── 1. Load dataset ──────────────────────────────────────────────────────────
df = pd.read_csv('prism_farm_dataset.csv')

# ── 2. Feature engineering ───────────────────────────────────────────────────
def compute_features(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    # Temperature-Humidity Index (THI) — industry standard heat stress metric
    df['thi'] = df['temperature_c'] - (0.55 - 0.0055 * df['humidity_pct']) * (df['temperature_c'] - 14.5)
    # Rolling averages (last 3 readings) for trend context
    df['temp_avg3']     = df['temperature_c'].rolling(3, min_periods=1).mean()
    df['humidity_avg3'] = df['humidity_pct'].rolling(3, min_periods=1).mean()
    return df

df = compute_features(df)

FEATURES = ['temperature_c', 'humidity_pct', 'thi', 'weight_change_kg',
            'feed_intake_kg', 'temp_avg3', 'humidity_avg3']

X = df[FEATURES]
y = df['condition']

# ── 3. Train / test split ────────────────────────────────────────────────────
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

# ── 4. Train Decision Tree ───────────────────────────────────────────────────
model = DecisionTreeClassifier(
    max_depth=5,
    min_samples_leaf=5,
    random_state=42
)
model.fit(X_train, y_train)

# ── 5. Evaluate ──────────────────────────────────────────────────────────────
y_pred = model.predict(X_test)
print("=== Farm-Level Model Evaluation ===")
print(f"Accuracy: {accuracy_score(y_test, y_pred):.2%}")
print(classification_report(y_test, y_pred))

# ── 6. Save model ────────────────────────────────────────────────────────────
joblib.dump(model, 'prism_farm_model.pkl')
print("Model saved → prism_farm_model.pkl")

# ── 7. Insight & recommendation generator ───────────────────────────────────
def generate_farm_output(row: dict) -> dict:
    """
    row: dict with keys temperature_c, humidity_pct, thi,
                        weight_change_kg, feed_intake_kg
    Returns: condition (str), insights (list), recommendations (list)
    """
    model = joblib.load('prism_farm_model.pkl')

    input_df = pd.DataFrame([row])
    input_df = compute_features(input_df)
    prediction = model.predict(input_df[FEATURES])[0]

    thi              = input_df['thi'].iloc[0]
    temp             = row['temperature_c']
    hum              = row['humidity_pct']
    wt_change        = row['weight_change_kg']
    feed             = row['feed_intake_kg']

    insights        = []
    recommendations = []

    # Temperature insights
    if temp > 32:
        insights.append(f"Barn temperature is critically high at {temp}°C — severe heat stress zone.")
        recommendations.append("Activate cooling system immediately and increase ventilation.")
    elif temp > 25:
        insights.append(f"Barn temperature ({temp}°C) is above the thermoneutral zone (18–25°C).")
        recommendations.append("Monitor pigs closely. Consider pre-cooling or misting systems.")

    # Humidity insights
    if hum > 90:
        insights.append(f"Humidity is critically high at {hum}% — compounds heat stress significantly.")
        recommendations.append("Improve barn ventilation. Check drainage and reduce water waste.")
    elif hum > 80:
        insights.append(f"Humidity ({hum}%) is elevated above optimal range (60–80%).")
        recommendations.append("Increase airflow. Avoid overcrowding.")

    # THI insights
    if thi >= 26.11:
        insights.append(f"THI is {thi:.1f} — farm is in the DANGER zone for heat stress.")
        recommendations.append("Emergency: reduce stocking density, provide cool drinking water.")
    elif thi >= 23.33:
        insights.append(f"THI is {thi:.1f} — farm is in the ALERT zone.")
        recommendations.append("Increase monitoring frequency. Pre-cool barn in the afternoon.")

    # Weight change insights
    if wt_change < 0:
        insights.append(f"Average weight change is negative ({wt_change:.2f} kg/day) — pigs may be losing weight.")
        recommendations.append("Review feed quality and quantity. Check for illness or heat anorexia.")
    elif wt_change < 0.3:
        insights.append(f"Weight gain ({wt_change:.2f} kg/day) is below expected levels.")
        recommendations.append("Check feed intake and consider nutritional assessment.")

    # Feed intake insights
    if feed < 1.5:
        insights.append(f"Feed intake is low at {feed:.2f} kg/day — possible heat anorexia or illness.")
        recommendations.append("Shift feeding time to cooler parts of day (early morning / evening).")

    if not insights:
        insights.append("Farm conditions are within normal ranges. Pigs appear healthy.")
        recommendations.append("Continue current management routine.")

    return {
        "condition":       prediction,
        "insights":        insights,
        "recommendations": recommendations,
    }

# ── 8. Example prediction ────────────────────────────────────────────────────
if __name__ == '__main__':
    sample = {
        'temperature_c':    30.5,
        'humidity_pct':     85.0,
        'weight_change_kg': 0.25,
        'feed_intake_kg':   1.8,
        'medicine_given':   0,
    }
    result = generate_farm_output(sample)
    print("\n=== Sample Prediction ===")
    for k, v in result.items():
        print(f"{k}: {v}")
