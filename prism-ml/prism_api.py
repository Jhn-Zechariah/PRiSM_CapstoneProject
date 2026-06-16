"""
PRISM ML API
FastAPI backend — two endpoints:
  POST /api/farm/analyze  → farm-level condition (Good / Needs Attention / High Risk)
  POST /api/pig/analyze   → per-pig weight status (Normal / Underweight / Overweight)
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import date

# ── Import ML functions ───────────────────────────────────────────────────────
from prism_farm_ml import generate_farm_output
from prism_pig_weight_ml import generate_pig_output

app = FastAPI(title="PRISM ML API")

# Allow Flutter app to call this API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─────────────────────────────────────────────────────────────────────────────
# HEALTH CHECK
# ─────────────────────────────────────────────────────────────────────────────
@app.get("/")
def root():
    return {"message": "PRISM ML API is running..."}

# ─────────────────────────────────────────────────────────────────────────────
# ENDPOINT 1 — Farm-level analysis
# Called by dashboard_screen.dart → MlService.analyzeFarm()
#
# Input fields (from FarmDataService):
#   temperature_c    → 24hr avg from temperature_readings (tempAvg field)
#   humidity_pct     → 24hr avg from humidity_readings (humidityAvg field)
#   weight_change_kg → avg ADG across all active pigs
#   feed_intake_kg   → total feed amount logged today across all pigs
#   medicine_given   → optional (0 or 1)
# ─────────────────────────────────────────────────────────────────────────────
class FarmReading(BaseModel):
    temperature_c:    float
    humidity_pct:     float
    weight_change_kg: float = 0.0
    feed_intake_kg:   float = 0.0
    medicine_given:   int   = 0

@app.post("/api/farm/analyze")
def analyze_farm(data: FarmReading):
    try:
        row = {
            'temperature_c':    data.temperature_c,
            'humidity_pct':     data.humidity_pct,
            'weight_change_kg': data.weight_change_kg,
            'feed_intake_kg':   data.feed_intake_kg,
            'medicine_given':   data.medicine_given,
        }
        result = generate_farm_output(row)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ─────────────────────────────────────────────────────────────────────────────
# ENDPOINT 2 — Per-pig weight analysis
# Called by pig_profile_card.dart → MlService.analyzePig()
#
# Input fields (from AppPig model):
#   pig_id         → pigId from Firestore
#   birth_date     → birthDate as YYYY-MM-DD string
#   current_weight → currentWeightKg from Firestore
#   birth_weight   → birthWeightKg from Firestore
#
# Returns:
#   classification → "Normal" / "Underweight" / "Overweight"
#   insight        → single string describing weight status
#   recommendation → single string action for the farmer
# ─────────────────────────────────────────────────────────────────────────────
class PigReading(BaseModel):
    pig_id:         str
    birth_date:     str    # format: YYYY-MM-DD
    current_weight: float  # kg
    birth_weight:   float  # kg

@app.post("/api/pig/analyze")
def analyze_pig(data: PigReading):
    try:
        pig = {
            'pig_id':         data.pig_id,
            'birth_date':     data.birth_date,
            'current_weight': data.current_weight,
            'birth_weight':   data.birth_weight,
        }
        result = generate_pig_output(pig)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))