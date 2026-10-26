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


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/predict/farm", dependencies=[Depends(check_key)])
def predict_farm(d: FarmIn):
    return predictor.predict_farm(d.body_temp, d.ambient_temp, d.humidity)

