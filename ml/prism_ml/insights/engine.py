"""Evidence-based actionable insight sentences.

This component is deliberately separate from the classifier: it never decides the thermal status. It
explains the status it is given (from the trained model, or an operational state) using the actual
measurements, the data-quality findings and the referenced guidance in ``references.py``. The
sentences are written rules, not the output of a trained model.
"""
from __future__ import annotations

from typing import TYPE_CHECKING, Optional

from prism_ml.config import load_config
from prism_ml.features.contract import compute_thi
from prism_ml.insights.references import REFERENCES, cite
from prism_ml.reading import (CLASSIFICATION_UNAVAILABLE, INSUFFICIENT_DATA, SENSOR_CHECK_REQUIRED, UNCERTAIN,
                              SensorReading)

if TYPE_CHECKING:
    from prism_ml.models.inference import Assessment

THI_FINISHER_REFERENCE_LEVEL = 84.0  # Vermeer & Aarnink (2023): THI above 84 = heat stress for finishers

FRIENDLY = {
    "air_temp_c": "air temperature",
    "relative_humidity_pct": "humidity",
    "thermal_top4_mean_c": "warmest thermal-camera area",
}


def _s(text: str, kind: str, *refs: str) -> dict:
    return {"text": text, "kind": kind, "references": cite(*refs)}


def _observation_sentence(m: dict) -> Optional[dict]:
    parts = []
    if m.get("air_temp_c") is not None:
        parts.append(f"air temperature {m['air_temp_c']:.1f} °C")
    if m.get("relative_humidity_pct") is not None:
        parts.append(f"humidity {m['relative_humidity_pct']:.0f} %")
    if m.get("thermal_max_c") is not None:
        parts.append(f"warmest thermal-camera reading {m['thermal_max_c']:.1f} °C")
    if not parts:
        return None
    refs = ["ADAFRUIT_DHT"] if (m.get("air_temp_c") is not None or m.get("relative_humidity_pct") is not None) else []
    text = "Latest readings: " + ", ".join(parts) + "."
    if m.get("thermal_max_c") is not None:
        text += (" The thermal camera measures apparent surface temperature (about ±2.5 °C accuracy), which is not "
                 "the same as the pigs' body (core) temperature.")
        refs.append("ADAFRUIT_AMG8833")
    return _s(text, "observation", *refs)


def _model_support_sentences(a: "Assessment", reading: SensorReading, metadata: dict) -> list[dict]:
    """Explain which measurements resemble the reviewer-labelled training sessions of the predicted class."""
    medians = metadata.get("class_feature_medians") or {}
    if a.status not in medians:
        return []
    from prism_ml.features.contract import build_features  # local import: reading already passed quality checks
    feats = build_features(reading)
    out = []
    for f, label in FRIENDLY.items():
        here = medians[a.status].get(f)
        if here is None:
            continue
        closest = min(medians, key=lambda c: abs(medians[c][f] - feats[f]))
        if closest == a.status:
            out.append(f"{label} {feats[f]:.1f} (typical in reviewer-labelled '{a.status}' sessions: {here:.1f})")
    if not out:
        return []
    return [_s("Measurements that resemble past expert-labelled '" + a.status + "' conditions: " + "; ".join(out) + ".",
               "evidence")]


def _thi_context(reading: SensorReading) -> Optional[dict]:
    if reading.air_temp_c is None or reading.relative_humidity_pct is None:
        return None
    if not (reading.air_temp_valid and reading.humidity_valid):
        return None
    thi = compute_thi(float(reading.air_temp_c), float(reading.relative_humidity_pct))
    if thi <= THI_FINISHER_REFERENCE_LEVEL:
        return None
    return _s(f"The temperature-humidity index (THI) from the current air readings is {thi:.0f}. A published heat-stress "
              f"review reports THI above {THI_FINISHER_REFERENCE_LEVEL:.0f} as a heat-stress level for finishing pigs. "
              "This is reference information, not a PRISM classification; check the pigs directly.",
              "reference_context", "VERMEER2023")


def _check_pigs_sentence(kind: str = "action") -> dict:
    return _s("Look at the pigs: fast breathing (more than about 50 breaths per minute at rest), panting or "
              "open-mouth breathing, lying apart from each other, wallowing in dung or a fouled pen, and low "
              "activity are signs that pigs are struggling with heat.", kind, "VERMEER2023")


def _water_sentences(reading: SensorReading) -> list[dict]:
    low = load_config("data_quality")["water_low_pct"]
    if reading.water_valid is False:
        return [_s("The water-level sensor reading is not valid; check the water tank by hand so drinking and "
                   "misting water stay available.", "data_quality")]
    if reading.water_valid and reading.water_level_pct is not None and reading.water_level_pct < low:
        return [_s(f"The water tank reads {reading.water_level_pct:.0f} %. Refill it so drinking and misting water "
                   "remain available.", "action", "VERMEER2023")]
    return []


def build_insights(a: "Assessment", reading: SensorReading, metadata: Optional[dict]) -> tuple[list[dict], list[dict]]:
    s: list[dict] = []
    obs = _observation_sentence(a.measurements)

    if a.status in (INSUFFICIENT_DATA, SENSOR_CHECK_REQUIRED):
        issues = [i for i in a.data_quality["issues"] if i["severity"] in ("missing", "fault")]
        lead = ("PRISM cannot assess the pigs' thermal condition right now because the sensor data are incomplete or "
                "out of date." if a.status == INSUFFICIENT_DATA else
                "PRISM cannot assess the pigs' thermal condition right now because a sensor appears to be faulty or "
                "uncalibrated.")
        s.append(_s(lead, "status"))
        for i in issues[:4]:
            s.append(_s(i["message"], "data_quality"))
        s.append(_s("Check the device's power, Wi-Fi connection and sensor wiring, and make sure nothing is blocking "
                    "the thermal camera. Until readings return, check the pigs in person.", "action"))
        s.append(_check_pigs_sentence())

    elif a.status == CLASSIFICATION_UNAVAILABLE:
        s.append(_s("No Good / Needs Attention / High Risk status is shown because PRISM's thermal-status model has not "
                    "yet been validated with expert-labelled data from the farm.", "status"))
        if obs:
            s.append(obs)
        thi = _thi_context(reading)
        if thi:
            s.append(thi)
        s.append(_check_pigs_sentence())
        s.append(_s("Keep clean drinking water available and the pen well ventilated during hot periods.", "action",
                    "VERMEER2023"))

    elif a.status == UNCERTAIN:
        why = ("the current readings are outside the conditions the model was validated on"
               if a.reason == "outside_validated_range" else "the model is not confident about the current readings")
        s.append(_s(f"PRISM cannot give a reliable status right now because {why}. Treat the condition as unknown, "
                    "not as safe.", "status"))
        if obs:
            s.append(obs)
        thi = _thi_context(reading)
        if thi:
            s.append(thi)
        s.append(_check_pigs_sentence())

    elif a.status == "Good":
        s.append(_s("The monitored conditions indicate a favourable thermal status.", "status"))
        if obs:
            s.append(obs)
        s.extend(_model_support_sentences(a, reading, metadata or {}))
        s.append(_s("Continue monitoring temperature, humidity, drinking-water availability and the pigs' behaviour.",
                    "action", "VERMEER2023"))

    elif a.status == "Needs Attention":
        s.append(_s("The current readings indicate a potentially concerning thermal condition.", "status"))
        if obs:
            s.append(obs)
        s.extend(_model_support_sentences(a, reading, metadata or {}))
        s.append(_s("When pigs cannot lose enough heat they become less active, eat less and breathe faster; acting "
                    "early helps prevent heat stress.", "why", "VERMEER2023"))
        s.append(_s("Improve airflow and ventilation in the pen, and check that drinkers deliver clean, cool water "
                    "with good flow.", "action", "VERMEER2023"))
        s.append(_check_pigs_sentence())
        s.append(_s("If misting is available, consider running the sprinkler, where it is safe to do so.", "action",
                    "VERMEER2023", "PRISM2026"))

    elif a.status == "High Risk":
        s.append(_s("The monitored conditions indicate a high level of concern. Assess the pigs now.", "status"))
        if obs:
            s.append(obs)
        s.extend(_model_support_sentences(a, reading, metadata or {}))
        s.append(_s("Without enough cooling, the pigs' body temperature can keep rising, which harms their welfare "
                    "and can be life-threatening.", "why", "VERMEER2023"))
        s.append(_s("Maximise ventilation and air movement, make sure every pig can reach clean water, and run the "
                    "misting system or wet the pigs with water where it is safe to do so (keep water away from "
                    "electrical equipment).", "action", "VERMEER2023", "PRISM2026"))
        s.append(_s("Avoid moving, handling or treating pigs during the hottest part of the day unless it is urgent.",
                    "action", "VERMEER2023"))
        s.append(_s("Contact a veterinarian if any pig shows open-mouth breathing, heavy panting, collapse, or does "
                    "not get up when you approach.", "safety", "VERMEER2023", "PRISM2026"))

    if a.status_kind == "thermal" and a.confidence is not None:
        s.append(_s(f"This status comes from PRISM's trained model (model confidence {a.confidence:.0%}). It is based on "
                    "sensor readings only and is not a diagnosis.", "transparency", "PRISM2026"))
    s.extend(_water_sentences(reading))

    used = sorted({r for item in s for r in item["references"]})
    refs = [{"id": r, "citation": REFERENCES[r]["citation"], "url": REFERENCES[r]["url"]} for r in used]
    return s, refs
