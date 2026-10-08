"""Rule layer that turns a predicted class (+ the factors behind it) into plain-language advice.
Wording is deliberately non-diagnostic."""
from ml.features import THI_LEVEL_NAMES, thi_level, body_level


def farm_advice(status, f):
    tips = []
    t_lvl, b_lvl = thi_level(f["thi"]), body_level(f["body_temp"])
    if status == "High Risk":
        tips.append("Possible heat stress risk. Turn on cooling (sprinklers/fans) now and check the pigs "
                    "for panting, lethargy, or reduced feeding.")
    if t_lvl >= 1:
        tips.append(f"Temperature-humidity index is at the {THI_LEVEL_NAMES[t_lvl]} level. "
                    "Improve ventilation and shade, and avoid handling or moving pigs in the hottest hours.")
    if f["humidity"] > 80:
        tips.append("Humidity is high, which makes it harder for pigs to lose heat. Increase airflow.")
    if b_lvl >= 1:
        tips.append("Measured body surface temperature is elevated. Re-check the reading and inspect "
                    "the pigs; contact a veterinarian if it persists.")
    if not tips:
        tips.append("Conditions are within the normal range. Continue regular monitoring.")
    return tips


def growth_advice(status, f, ref_adg_g):
    tips = []
    if status == "Below Expected":
        tips.append("Weight is below the reference curve for this age. Review feed amount, water access, "
                    "and heat conditions.")
        tips.append("If the pig also looks unwell or the gap keeps widening, consult a veterinarian.")
    elif status == "Above Expected":
        tips.append("Weight is above the reference curve for this age. Review feed portions and keep "
                    "weighing regularly.")
    else:
        tips.append("Weight is reasonably consistent with the reference curve.")
    if f["adg_g"] < 0.8 * ref_adg_g:
        tips.append("Recent daily gain is below the reference rate. Check feed intake and cooling conditions.")
    return tips
