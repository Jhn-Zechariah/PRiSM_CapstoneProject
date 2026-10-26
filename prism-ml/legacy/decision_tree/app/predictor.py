"""Model loading + prediction logic. No web-framework imports, so it can be tested on its own."""
import json
from pathlib import Path

import joblib
import pandas as pd

from ml.features import THI_LEVEL_NAMES, build_farm_features, thi_level
from app.recommend import farm_advice

MODELS = Path(__file__).resolve().parent.parent / "models"

DISCLAIMER = ("This is a monitoring aid based on PRISM operational thresholds. "
              "It is not a veterinary diagnosis.")


def _load(name):
    model = joblib.load(MODELS / f"{name}.pkl")
    meta = json.loads((MODELS / f"{name}_meta.json").read_text())
    return model, meta["features"]


farm_model, FARM_F = _load("farm_model")


def predict_farm(body_temp, ambient_temp, humidity):
    f = build_farm_features(body_temp, ambient_temp, humidity)
    X = pd.DataFrame([f])[FARM_F]
    status = str(farm_model.predict(X)[0])
    proba = {str(c): round(float(p), 3) for c, p in zip(farm_model.classes_, farm_model.predict_proba(X)[0])}
    return {"status": status,
            "thi": round(f["thi"], 1),
            "thi_level": THI_LEVEL_NAMES[thi_level(f["thi"])],
            "confidence": proba,
            "recommendations": farm_advice(status, f),
            "disclaimer": DISCLAIMER}

