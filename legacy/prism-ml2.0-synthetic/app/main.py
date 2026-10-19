"""FastAPI service.  Local run:  uvicorn app.main:app --reload"""
import os

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

from app import predictor

app = FastAPI(title="PRISM ML API", version="1.0.0")

API_KEY = os.environ.get("PRISM_API_KEY")        # unset = no key required (local testing)


def check_key(x_api_key: str = Header(default=None)):
    if API_KEY and x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Unauthorized")


class FarmIn(BaseModel):
    body_temp: float = Field(ge=25, le=45, description="Body surface temperature (deg C)")
    ambient_temp: float = Field(ge=5, le=55, description="Ambient temperature (deg C)")
    humidity: float = Field(ge=0, le=100, description="Relative humidity (%)")


class PigGrowthIn(BaseModel):
    age_days: int = Field(ge=0, le=400)
    current_weight_kg: float = Field(gt=0, le=400)
    previous_weight_kg: float = Field(gt=0, le=400)
    days_between: int = Field(ge=1, le=120, description="Days between the two weigh-ins")


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/predict/farm", dependencies=[Depends(check_key)])
def predict_farm(d: FarmIn):
    return predictor.predict_farm(d.body_temp, d.ambient_temp, d.humidity)


@app.post("/predict/pig-growth", dependencies=[Depends(check_key)])
def predict_pig_growth(d: PigGrowthIn):
    return predictor.predict_pig_growth(d.age_days, d.current_weight_kg,
                                        d.previous_weight_kg, d.days_between)
