"""
PRISM - FastAPI Backend with Firebase Authentication
Connects both ML models to the PRISM mobile/web app securely.

Run with:  uvicorn prism_api:app --reload --host 0.0.0.0 --port 8000
"""

from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel
from typing import Optional
import pandas as pd
import joblib
from dotenv import load_dotenv
from datetime import date
import firebase_admin
import os
from firebase_admin import credentials, auth

load_dotenv()

app = FastAPI(title="PRISM ML API", version="1.0.0")
security = HTTPBearer()

# ── Firebase Admin SDK Initialization ─────────────────────────────────────────
try:
    # Look for the path in .env, fallback to the string if not found
    cred_path = os.getenv("FIREBASE_CREDENTIALS_PATH", "firebase_credentials.json")
    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred)
    print("🔥 Firebase Admin SDK initialized successfully!")
except Exception as e:
    print(f"❌ Failed to initialize Firebase Admin SDK: {e}")

# ── Firebase Token Verification Dependency ───────────────────────────────────
def verify_firebase_token(cred: HTTPAuthorizationCredentials = Depends(security)):
    """Middleware dependency to check for a valid Firebase token in headers."""
    token = cred.credentials
    try:
        # ADD clock_skew_seconds=10 right here!
        decoded_token = auth.verify_id_token(token, clock_skew_seconds=10)
        return decoded_token
    except Exception as e:
        print(f"❌ TOKEN REJECTION REASON: {e}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid, expired, or missing Firebase authentication token.",
        )

# ── CORS ──────────────────────────────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Schemas ───────────────────────────────────────────────────────────────────
class FarmReading(BaseModel):
    temperature_c:    float
    humidity_pct:     float
    weight_change_kg: float = 0.0
    feed_intake_kg:   float = 0.0
    medicine_given:   Optional[int] = 0

class PigRecord(BaseModel):
    pig_id:         str
    birth_date:     str
    current_weight: float
    birth_weight:   float

# ── Feature Configurations ───────────────────────────────────────────────────
FARM_FEATURES = [
    'temperature_c', 'humidity_pct', 'thi',
    'weight_change_kg', 'feed_intake_kg',
    'temp_avg3', 'humidity_avg3'
]

PIG_FEATURES = [
    'age_days', 'current_weight', 'birth_weight',
    'adg', 'weight_deviation_pct', 'adg_deviation_pct'
]

GROWTH_STANDARDS = {
    'piglet':   {'age_range': (0,   21),  'weight_range': (1.0,  6.5),   'adg_target': 0.25},
    'nursery':  {'age_range': (22,  70),  'weight_range': (6.5,  25.0),  'adg_target': 0.38},
    'grower':   {'age_range': (71,  120), 'weight_range': (25.0, 60.0),  'adg_target': 0.65},
    'finisher': {'age_range': (121, 170), 'weight_range': (60.0, 110.0), 'adg_target': 0.80},
}

def get_stage(age_days: int):
    for stage, data in GROWTH_STANDARDS.items():
        lo, hi = data['age_range']
        if lo <= age_days <= hi:
            return stage, data
    return 'market_ready', None

# ── Open Health Check (No security required) ──────────────────────────────────
@app.get("/")
def root():
    return {
        "message": "PRISM ML API is running.",
        "endpoints": ["/api/farm/analyze", "/api/pig/analyze"]
    }

# ── ENDPOINT 1: Farm-level analysis (SECURED) ────────────────────────────────
@app.post("/api/farm/analyze")
def analyze_farm(reading: FarmReading, user: dict = Depends(verify_firebase_token)):
    try:
        model = joblib.load('prism_farm_model.pkl')
    except FileNotFoundError:
        raise HTTPException(
            status_code=500,
            detail="Farm model not found. Run: python prism_farm_ml.py"
        )

    row = reading.dict()
    df  = pd.DataFrame([row])
    df['thi']           = df['temperature_c'] - (0.55 - 0.0055 * df['humidity_pct']) * (df['temperature_c'] - 14.5)
    df['temp_avg3']     = df['temperature_c']
    df['humidity_avg3'] = df['humidity_pct']

    prediction = model.predict(df[FARM_FEATURES])[0]
    thi        = float(df['thi'].iloc[0])

    temp  = row['temperature_c']
    hum   = row['humidity_pct']
    wt    = row['weight_change_kg']
    feed  = row['feed_intake_kg']

    insights        = []
    recommendations = []

    if temp > 32:
        insights.append(f"Barn temperature is critically high at {temp}°C — severe heat stress zone.")
        recommendations.append("Activate cooling system immediately and increase ventilation.")
    elif temp > 25:
        insights.append(f"Barn temperature ({temp}°C) is above the thermoneutral zone (18–25°C).")
        recommendations.append("Monitor pigs closely. Consider pre-cooling or misting systems.")

    if hum > 90:
        insights.append(f"Humidity is critically high at {hum}% — compounds heat stress significantly.")
        recommendations.append("Improve barn ventilation. Check drainage and reduce water waste.")
    elif hum > 80:
        insights.append(f"Humidity ({hum}%) is elevated above optimal range (60–80%).")
        recommendations.append("Increase airflow. Avoid overcrowding.")

    if thi >= 26.11:
        insights.append(f"THI is {thi:.1f} — farm is in the DANGER zone for heat stress.")
        recommendations.append("Emergency: reduce stocking density, provide cool drinking water.")
    elif thi >= 23.33:
        insights.append(f"THI is {thi:.1f} — farm is in the ALERT zone.")
        recommendations.append("Increase monitoring frequency. Pre-cool barn in the afternoon.")

    if wt < 0:
        insights.append(f"Average weight change is negative ({wt:.2f} kg/day) — pigs may be losing weight.")
        recommendations.append("Review feed quality and quantity. Check for illness or heat anorexia.")
    elif wt < 0.3 and wt > 0:
        insights.append(f"Weight gain ({wt:.2f} kg/day) is below expected levels.")
        recommendations.append("Check feed intake and consider nutritional assessment.")

    if feed < 1.5 and feed > 0:
        insights.append(f"Feed intake is low at {feed:.2f} kg/day — possible heat anorexia or illness.")
        recommendations.append("Shift feeding time to cooler parts of day (early morning / evening).")

    if not insights:
        insights.append("Farm conditions are within normal ranges. Pigs appear healthy.")
        recommendations.append("Continue current management routine.")

    return {
        "condition":       prediction,
        "thi":             round(thi, 2),
        "insights":        insights,
        "recommendations": recommendations,
        "verified_uid":    user['uid']  # Proof that the server identified the user
    }

# ── ENDPOINT 2: Per-pig weight analysis (SECURED) ─────────────────────────────
@app.post("/api/pig/analyze")
def analyze_pig(pig: PigRecord, user: dict = Depends(verify_firebase_token)):
    try:
        model = joblib.load('prism_pig_weight_model.pkl')
    except FileNotFoundError:
        raise HTTPException(
            status_code=500,
            detail="Pig weight model not found. Run: python prism_pig_weight_ml.py"
        )

    birth    = date.fromisoformat(pig.birth_date)
    age_days = max((date.today() - birth).days, 1)
    stage, std = get_stage(age_days)

    adg = (pig.current_weight - pig.birth_weight) / age_days

    if std:
        lo, hi   = std['weight_range']
        mid      = (lo + hi) / 2
        wt_dev   = ((pig.current_weight - mid) / mid) * 100
        adg_dev  = ((adg - std['adg_target']) / std['adg_target']) * 100
        exp_lo, exp_hi = lo, hi
        adg_target     = std['adg_target']
    else:
        wt_dev = adg_dev = 0.0
        exp_lo, exp_hi  = 100.0, 120.0
        adg_target      = 0.0

    input_df = pd.DataFrame([{
        'age_days':             age_days,
        'current_weight':       pig.current_weight,
        'birth_weight':         pig.birth_weight,
        'adg':                  adg,
        'weight_deviation_pct': wt_dev,
        'adg_deviation_pct':    adg_dev,
    }])

    classification = model.predict(input_df[PIG_FEATURES])[0]

    insight = ""
    recommendation = ""

    if classification == 'Normal':
        insight = (
            f"Pig is {pig.current_weight:.1f} kg at {age_days} days old — within the expected "
            f"range of {exp_lo:.1f}–{exp_hi:.1f} kg for the {stage} stage. "
            f"ADG is {adg:.3f} kg/day, on track with the target of {adg_target:.2f} kg/day."
        )
        recommendation = "Continue current feeding and care routine. Record next weight at the scheduled weigh-in."

    elif classification == 'Underweight':
        insight = (
            f"Pig is {pig.current_weight:.1f} kg at {age_days} days old — {abs(wt_dev):.1f}% below "
            f"the expected midpoint for the {stage} stage ({exp_lo:.1f}–{exp_hi:.1f} kg). "
            f"ADG of {adg:.3f} kg/day is below the target of {adg_target:.2f} kg/day."
        )
        if abs(wt_dev) > 30:
            recommendation = "Weight gap is significant. Review feed quality and quantity. Check for signs of illness, parasites, or bullying by pen mates. Consult a veterinarian if no improvement in 7 days."
        else:
            recommendation = "Review feeding schedule and ensure this pig has access to the feeder. Check for signs of illness: lethargy, diarrhea, or labored breathing. Consider vitamin supplementation."

    else:  # Overweight
        insight = (
            f"Pig is {pig.current_weight:.1f} kg at {age_days} days old — {wt_dev:.1f}% above "
            f"the expected midpoint for the {stage} stage ({exp_lo:.1f}–{exp_hi:.1f} kg)."
        )
        if stage == 'finisher' and pig.current_weight >= 100:
            recommendation = f"Pig has reached {pig.current_weight:.1f} kg. Consider scheduling for market soon to optimize carcass quality. Adjust feed ration to reduce excess fat deposition."
        else:
            recommendation = "Adjust feed ration to prevent excess fat deposition. Monitor growth rate and review feed composition."

    return {
        "pig_id":         pig.pig_id,
        "stage":          stage,
        "age_days":       age_days,
        "adg":            round(adg, 3),
        "classification": classification,
        "insight":        insight,
        "recommendation": recommendation,
        "verified_uid":    user['uid']
    }