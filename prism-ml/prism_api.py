"""
PRISM - FastAPI Backend
Connects both ML models to the PRISM mobile/web app.

Run with:  uvicorn prism_api:app --reload --port 8000
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional
import pandas as pd
import joblib
import numpy as np
from datetime import date

app = FastAPI(title="PRISM ML API", version="1.0.0")

# ── Schemas ──────────────────────────────────────────────────────────────────
class FarmReading(BaseModel):
    temperature_c:    float   # barn ambient temp (°C)
    humidity_pct:     float   # relative humidity (%)
    weight_change_kg: float   # avg daily weight change (kg)
    feed_intake_kg:   float   # avg daily feed intake (kg)
    medicine_given:   Optional[int] = 0

class PigRecord(BaseModel):
    pig_id:         str
    birth_date:     str     # ISO format: YYYY-MM-DD
    current_weight: float   # kg
    birth_weight:   float   # kg

# ── Farm-level endpoint ───────────────────────────────────────────────────────
FARM_FEATURES = ['temperature_c', 'humidity_pct', 'thi', 'weight_change_kg',
                 'feed_intake_kg', 'temp_avg3', 'humidity_avg3']

@app.post("/api/farm/analyze")
def analyze_farm(reading: FarmReading):
    try:
        model = joblib.load('prism_farm_model.pkl')
    except FileNotFoundError:
        raise HTTPException(status_code=500, detail="Farm model not found. Train model first.")

    row = reading.dict()
    df  = pd.DataFrame([row])
    df['thi']          = df['temperature_c'] - (0.55 - 0.0055 * df['humidity_pct']) * (df['temperature_c'] - 14.5)
    df['temp_avg3']    = df['temperature_c']
    df['humidity_avg3']= df['humidity_pct']

    prediction = model.predict(df[FARM_FEATURES])[0]
    thi        = float(df['thi'].iloc[0])

    insights        = []
    recommendations = []

    if row['temperature_c'] > 32:
        insights.append(f"Barn temperature is critically high at {row['temperature_c']}°C.")
        recommendations.append("Activate cooling system immediately.")
    elif row['temperature_c'] > 25:
        insights.append(f"Barn temperature ({row['temperature_c']}°C) is above the thermoneutral zone.")
        recommendations.append("Monitor pigs closely and consider pre-cooling.")

    if row['humidity_pct'] > 90:
        insights.append(f"Humidity is critically high at {row['humidity_pct']}%.")
        recommendations.append("Improve ventilation and check drainage.")
    elif row['humidity_pct'] > 80:
        insights.append(f"Humidity ({row['humidity_pct']}%) is above optimal range.")
        recommendations.append("Increase airflow.")

    if thi >= 26.11:
        insights.append(f"THI {thi:.1f} — farm is in the DANGER zone.")
        recommendations.append("Emergency: cool barn, provide cold water immediately.")
    elif thi >= 23.33:
        insights.append(f"THI {thi:.1f} — farm is in the ALERT zone.")
        recommendations.append("Increase monitoring. Pre-cool barn during afternoon.")

    if row['weight_change_kg'] < 0:
        insights.append(f"Pigs may be losing weight ({row['weight_change_kg']:.2f} kg/day).")
        recommendations.append("Check feed quality and review for illness.")

    if row['feed_intake_kg'] < 1.5:
        insights.append(f"Low feed intake detected ({row['feed_intake_kg']:.2f} kg/day).")
        recommendations.append("Shift feeding to cooler parts of the day.")

    if not insights:
        insights.append("Farm conditions are within normal ranges.")
        recommendations.append("Continue current management routine.")

    return {
        "condition":       prediction,
        "thi":             round(thi, 2),
        "insights":        insights,
        "recommendations": recommendations,
    }

# ── Per-pig endpoint ──────────────────────────────────────────────────────────
GROWTH_STANDARDS = {
    'starter':  {'age_range': (0,  70),  'weight_range': (1.5, 30),  'adg_target': 0.35},
    'grower':   {'age_range': (71, 105), 'weight_range': (30,  60),  'adg_target': 0.60},
    'finisher': {'age_range': (106,160), 'weight_range': (60,  100), 'adg_target': 0.75},
}

def get_stage(age):
    for s, d in GROWTH_STANDARDS.items():
        if d['age_range'][0] <= age <= d['age_range'][1]:
            return s, d
    return 'market_ready', None

@app.post("/api/pig/analyze")
def analyze_pig(pig: PigRecord):
    try:
        model = joblib.load('prism_pig_weight_model.pkl')
    except FileNotFoundError:
        raise HTTPException(status_code=500, detail="Pig weight model not found. Train model first.")

    birth    = date.fromisoformat(pig.birth_date)
    age_days = (date.today() - birth).days
    stage, std = get_stage(age_days)

    adg = (pig.current_weight - pig.birth_weight) / age_days if age_days > 0 else 0

    if std:
        mid        = sum(std['weight_range']) / 2
        wt_dev     = ((pig.current_weight - mid) / mid) * 100
        adg_dev    = ((adg - std['adg_target']) / std['adg_target']) * 100
    else:
        wt_dev = adg_dev = 0

    input_df = pd.DataFrame([{
        'age_days':             age_days,
        'current_weight_kg':    pig.current_weight,
        'adg_kg_per_day':       adg,
        'weight_deviation_pct': wt_dev,
        'adg_deviation_pct':    adg_dev,
    }])

    classification = model.predict(input_df)[0]

    if classification == 'Normal':
        insight        = f"Pig is at {pig.current_weight:.1f} kg — within normal range for {stage} stage. ADG {adg:.3f} kg/day is on track."
        recommendation = "Continue current feeding and care routine."
    elif classification == 'Underweight':
        insight        = f"Pig is at {pig.current_weight:.1f} kg — {abs(wt_dev):.1f}% below expected for {stage} stage. ADG {adg:.3f} kg/day is below target."
        recommendation = "Review feeding schedule, check for illness or parasites. Consult vet if no improvement in 7 days."
    else:
        insight        = f"Pig is at {pig.current_weight:.1f} kg — {wt_dev:.1f}% above expected for {stage} stage."
        recommendation = "Adjust feed ration. Consider earlier market scheduling if over 100 kg."

    return {
        "pig_id":         pig.pig_id,
        "stage":          stage,
        "age_days":       age_days,
        "adg":            round(adg, 3),
        "classification": classification,
        "insight":        insight,
        "recommendation": recommendation,
    }

@app.get("/")
def root():
    return {"message": "PRISM ML API is running.", "endpoints": ["/api/farm/analyze", "/api/pig/analyze"]}
