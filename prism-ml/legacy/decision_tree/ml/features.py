"""
Shared reference data, thresholds and feature engineering.
Used by BOTH training (ml/make_datasets.py, ml/train.py) and the API (app/predictor.py),
so the model always sees features computed exactly the same way.

IMPORTANT: every constant marked [CITE] or [PROJECT-DEFINED] must be traced to a source
or disclosed as project-defined in the paper.
"""
import numpy as np

# =====================================================================
# FARM-LEVEL ENVIRONMENT MODEL  (inputs: body temp, ambient temp, humidity -> THI)
# =====================================================================
def compute_thi(temp_c, rh):
    """THI formula as given in Vermeer & Aarnink, 'Review on heat stress in pigs on farm'
    (Zenodo 10.5281/zenodo.7620726). [CITE] Output is on a Fahrenheit-style scale, so the
    thresholds below must use the same scale."""
    return (1.8 * temp_c + 32) - (0.55 - 0.0055 * rh) * (1.8 * temp_c - 26)


# [CITE or PROJECT-DEFINED] Livestock Weather Safety Index style categories
# (normal <=74, alert 75-78, danger 79-83, emergency >=84). Verify against your sources.
THI_ALERT, THI_DANGER, THI_EMERGENCY = 75.0, 79.0, 84.0

# [PROJECT-DEFINED] body SURFACE temperature (thermal camera) bands. Surface temp is lower than
# core/rectal temp; calibrate these with real AMG8833 readings from your pilot farm.
BODY_WARN, BODY_HIGH = 35.5, 37.0

THI_LEVEL_NAMES = {0: "Normal", 1: "Alert", 2: "Danger", 3: "Emergency"}


def thi_level(thi):
    return 3 if thi >= THI_EMERGENCY else 2 if thi >= THI_DANGER else 1 if thi >= THI_ALERT else 0


def body_level(body_temp):
    return 2 if body_temp >= BODY_HIGH else 1 if body_temp >= BODY_WARN else 0


def farm_label(thi, body_temp):
    """[PROJECT-DEFINED] combined rule: thi_level (0-3) + body_level (0-2)."""
    score = thi_level(thi) + body_level(body_temp)
    if score >= 3:
        return "High Risk"
    if score >= 1:
        return "Needs Attention"
    return "Good"


def build_farm_features(body_temp, ambient_temp, humidity):
    return {"body_temp": body_temp, "ambient_temp": ambient_temp, "humidity": humidity,
            "thi": compute_thi(ambient_temp, humidity)}


FARM_FEATURES = ["body_temp", "ambient_temp", "humidity", "thi"]
FARM_ABLATION_DROP = ["thi"]
