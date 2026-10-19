"""
Shared reference data, thresholds and feature engineering.
Used by BOTH training (ml/make_datasets.py, ml/train.py) and the API (app/predictor.py),
so the model always sees features computed exactly the same way.

IMPORTANT: every constant marked [CITE] or [PROJECT-DEFINED] must be traced to a source
or disclosed as project-defined in the paper.
"""
import numpy as np

# =====================================================================
# PER-PIG GROWTH MODEL
# =====================================================================
# PIC (2019) Wean-to-Finish Manual, Appendix J: reference curve for PIC-sired pigs.
# [CITE] Verify every value against the PDF before submitting.
REF_AGE = np.array([21, 28, 35, 42, 49, 56, 63, 70, 77, 84, 91, 98, 105, 112, 119,
                    126, 133, 140, 147, 154, 161, 168, 175, 182, 189, 196])
REF_WT = np.array([5.9, 7.3, 9.5, 12.2, 15.4, 19.8, 24.7, 29.9, 35.4, 41.3, 47.5, 54.0, 60.5,
                   67.3, 74.1, 81.0, 87.8, 94.6, 101.4, 108.0, 114.5, 121.0, 127.2, 133.2,
                   139.1, 144.8])                                   # kg
REF_ADG = np.array([np.nan, 190, 313, 394, 458, 621, 698, 738, 793, 843, 888, 915, 942, 965,
                    974, 978, 978, 974, 960, 951, 929, 915, 888, 865, 838, 815])  # g/day

MIN_AGE, MAX_AGE = int(REF_AGE.min()), int(REF_AGE.max())          # 21 - 196 days

# [PROJECT-DEFINED] operational growth bands (NOT veterinary cut-offs)
BELOW_PCT, ABOVE_PCT = 90.0, 110.0

# [PROJECT-DEFINED] production-stage age boundaries. Align with the `stage` values in your app.
def stage_of(age_days):
    """0 = Weanling/Nursery, 1 = Grower, 2 = Finisher"""
    return 0 if age_days < 70 else (1 if age_days < 126 else 2)

STAGE_NAMES = {0: "Weanling", 1: "Grower", 2: "Finisher"}


def reference_weight(age_days):
    return float(np.interp(age_days, REF_AGE, REF_WT))


def reference_adg(age_days):
    ok = ~np.isnan(REF_ADG)
    return float(np.interp(age_days, REF_AGE[ok], REF_ADG[ok]))


def growth_label(ratio_pct):
    if ratio_pct < BELOW_PCT:
        return "Below Expected"
    if ratio_pct > ABOVE_PCT:
        return "Above Expected"
    return "Within Expected"


def build_pig_features(age_days, weight, prev_weight, days_between):
    ref = reference_weight(age_days)
    gain = weight - prev_weight
    return {
        "age_days": age_days,
        "stage": stage_of(age_days),
        "current_weight": weight,
        "previous_weight": prev_weight,
        "days_between": days_between,
        "weight_gain": gain,
        "adg_g": gain / days_between * 1000.0,
        "reference_weight": ref,
        "growth_ratio": weight / ref * 100.0,
    }


PIG_FEATURES = ["age_days", "stage", "current_weight", "previous_weight", "days_between",
                "weight_gain", "adg_g", "reference_weight", "growth_ratio"]   # no pig ID
PIG_ABLATION_DROP = ["growth_ratio", "reference_weight"]   # for the ablation experiment

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
