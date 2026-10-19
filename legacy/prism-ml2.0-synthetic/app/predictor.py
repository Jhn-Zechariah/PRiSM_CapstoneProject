"""Model loading + prediction logic. No web-framework imports, so it can be tested on its own."""
import json
from pathlib import Path

import joblib
import pandas as pd

from ml.features import (MIN_AGE, MAX_AGE, STAGE_NAMES, THI_LEVEL_NAMES, build_farm_features,
                         build_pig_features, reference_adg, thi_level)
from app.recommend import farm_advice, growth_advice

MODELS = Path(__file__).resolve().parent.parent / "models"

DISCLAIMER = ("This is a monitoring aid based on a reference growth curve and PRISM operational "
              "thresholds. It is not a veterinary diagnosis.")


def _load(name):
    model = joblib.load(MODELS / f"{name}.pkl")
    meta = json.loads((MODELS / f"{name}_meta.json").read_text())
    return model, meta["features"]


farm_model, FARM_F = _load("farm_model")
pig_model, PIG_F = _load("pig_growth_model")


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


def predict_pig_growth(age_days, current_weight_kg, previous_weight_kg, days_between):
    if not (MIN_AGE <= age_days <= MAX_AGE):
        return {"status": "Out of reference range",
                "message": f"The reference curve covers {MIN_AGE}-{MAX_AGE} days of age.",
                "disclaimer": DISCLAIMER}
    f = build_pig_features(age_days, current_weight_kg, previous_weight_kg, days_between)
    X = pd.DataFrame([f])[PIG_F]
    status = str(pig_model.predict(X)[0])
    ref_adg = reference_adg(age_days)
    return {"status": status,
            "stage": STAGE_NAMES[f["stage"]],
            "growth_ratio_pct": round(f["growth_ratio"], 1),
            "reference_weight_kg": round(f["reference_weight"], 1),
            "adg_g_per_day": round(f["adg_g"]),
            "reference_adg_g_per_day": round(ref_adg),
            "recommendations": growth_advice(status, f, ref_adg),
            "disclaimer": DISCLAIMER}
