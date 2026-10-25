"""Adapters: assess/* and the active forecast model -> API responses.

Fail-safe: whenever the model is missing/broken, the input is invalid, or the reading is
stale/offline/too sparse, the rule-based result is returned with forecast = null and a
data-quality status that says why. Nothing here writes to Firestore or calls the ESP32.
"""
import math

import pandas as pd

from app.settings import api_config, max_future_s
from assess.growth import assess_growth
from assess.pen_thermal import COMPONENT as PEN_COMPONENT, assess_pen_thermal
from assess.response import inp, make_response
from assess.thi_band import assess_thi, band_index
from forecast.data import TARGET_COLUMN, to_grid
from forecast.features import feature_block, lookback_minutes

GOOD = ("ok", "warning")


def to_api(resp, dq, extra_warnings=(), forecast=None, model_version=None, method=None):
    return {
        "output": {"component": resp["component"], "status": resp["status"],
                   "status_label": resp["status_label"], "details": resp["details"]},
        "method": method or resp["method"],
        "reasons": resp["reasons"],
        "inputs_summary": resp["inputs"],
        "data_quality_status": dq,
        "data_quality_warnings": list(resp["data_quality_warnings"]) + list(extra_warnings),
        "config_warnings": resp["config_warnings"],
        "config_version": resp["config_version"],
        "model_version": model_version,
        "forecast": forecast,
        "timestamp": resp["timestamp"],
        "reference_type": resp["reference_type"],
        "advisory": True,
        "disclaimer": resp["disclaimer"],
    }


def freshness(ts, now):
    """(status, warning) for a reading timestamp against server time."""
    age = (now - ts).total_seconds()
    if age < -max_future_s():
        return "invalid", f"reading timestamp is {-age:.0f} s in the future"
    limit = api_config()["freshness"]["max_reading_age_s"]
    if age > limit:
        return "stale", f"latest reading is {age:.0f} s old (limit {limit} s)"
    return "ok", None


# ------------------------------------------------------------------ environment (B1 + B2)
def _readings_frame(readings, pen):
    rows = []
    for r in readings:
        def state(v, valid):
            return "sensor_offline" if valid is False else ("normal" if v is not None else "missing")
        rows.append({"effective_time_utc": r.timestamp.isoformat(), "time_basis": "device", "duplicate_of": "",
                     "pen_id": pen, "device_key": pen,
                     "dht_temp_c": r.dht_temp_c, "dht_temp_c__state": state(r.dht_temp_c, r.dht_temp_valid),
                     "dht_humidity_pct": r.dht_humidity_pct,
                     "dht_humidity_pct__state": state(r.dht_humidity_pct, r.dht_humidity_valid),
                     "sprinkler_on": r.sprinkler_on, "sprinkler_active_s": r.sprinkler_active_s})
    return pd.DataFrame(rows)


def forecast_from(readings, pen, model, meta, acfg):
    """Returns (forecast dict or None, warnings)."""
    fcfg, features = meta["training_config"], meta["features"]
    if meta.get("thi_formula") != acfg["assessment"]["thi"]["formula"]["expression"]:
        return None, ["forecast withheld: THI formula differs from the one the model was trained with"]
    grid, _ = to_grid(_readings_frame(readings, pen or "api"), fcfg, acfg)
    if grid.empty:
        return None, ["forecast withheld: no usable readings"]
    grid = grid.sort_values("time").reset_index(drop=True)
    target = TARGET_COLUMN[meta["target"]]
    step = fcfg["resample_minutes"]
    need_bins = lookback_minutes(fcfg) // step + 1
    window = grid.tail(need_bins)
    have = int(window[target].notna().sum()) if len(grid) >= need_bins else int(grid[target].notna().sum())
    pct = have / need_bins * 100
    min_pct = api_config()["forecast"]["min_history_coverage_pct"]
    if pct < min_pct:
        return None, [f"forecast withheld: recent history covers {pct:.0f}% of the model's "
                      f"{lookback_minutes(fcfg)}-min look-back (needs {min_pct}%)"]
    F, _ = feature_block(grid, fcfg, misting="mist_on_now" in features)
    missing = [f for f in features if f not in F.columns]
    if missing:
        return None, [f"forecast withheld: features not available from the request: {missing[:5]}"]
    current = grid[target].iloc[-1]
    if pd.isna(current):
        return None, ["forecast withheld: no usable value in the latest interval"]
    row = F[features].iloc[[-1]]
    blank_now = [f for f in features if f.endswith("_now") and pd.isna(row[f].iloc[0])]
    if blank_now:                                   # never let the imputer invent the current state
        return None, [f"forecast withheld: current value missing for {blank_now}"]
    pred = float(model.predict(row.to_numpy(dtype=float))[0])
    level = current + pred if fcfg["predict"] == "delta" else pred
    if not math.isfinite(level):
        return None, ["forecast withheld: model produced a non-finite value"]
    band = None
    t = acfg["assessment"]["thi"]
    cat = t["categories"].get(t["default_category"]) or {}
    if meta["target"] == "thi" and cat.get("thresholds"):
        band = t["band_keys"][band_index(level, cat["thresholds"], cat["hysteresis"] or 0)[0]]
    return {"target": meta["target"], "horizon_minutes": meta["horizon_minutes"], "value": round(level, 2),
            "projected_band": band, "model_version": meta["version"],
            "note": acfg["labels"]["forecast_note"]}, []


def environment(body, state, acfg, now):
    readings = sorted(body.readings, key=lambda r: r.timestamp)
    cur = readings[-1]
    dq, w = freshness(cur.timestamp, now)
    warnings = [w] if w else []
    t = None if cur.dht_temp_valid is False else cur.dht_temp_c
    h = None if cur.dht_humidity_valid is False else cur.dht_humidity_pct
    if t is None or h is None:
        dq = "offline" if (cur.dht_temp_valid is False or cur.dht_humidity_valid is False) else "insufficient"
        warnings.append("DHT22 reports the sensor offline" if dq == "offline" else "DHT22 value missing")
    resp = assess_thi(t, h, category=body.category, previous_band=body.previous_band,
                      observed_at=cur.timestamp, quality_flags=cur.quality_flags, cfg=acfg, now=now)
    if dq in GOOD:
        if resp["status"] == "unavailable":
            dq = "invalid"
        elif resp["status"] == "insufficient_data":
            dq = "insufficient"
        elif resp["data_quality_warnings"]:
            dq = "warning"

    model, meta, version, error = state.snapshot()
    forecast = None
    if model is None:
        warnings.append("forecast model failed to load; rule-based result only" if error
                        else "no approved forecast model is active; rule-based result only")
    elif dq not in GOOD:
        warnings.append(f"forecast withheld: data quality is {dq}")
    else:
        try:
            forecast, fw = forecast_from(readings, body.pen_id, model, meta, acfg)
        except Exception as e:                            # never fail the rule result because of the model
            forecast, fw = None, [f"forecast withheld: model error ({type(e).__name__})"]
        warnings += fw
    return to_api(resp, dq, warnings, forecast, version if forecast else None,
                  "rule+ML" if forecast else "rule")


# ------------------------------------------------------------------ A1
def pig_growth(body, acfg, now):
    pig = body.pig.model_dump(mode="json")
    weights = [w.model_dump(mode="json") for w in body.weights]
    resp = assess_growth(pig, weights, cfg=acfg, now=now)
    dq = ("insufficient" if resp["status"] == "insufficient_data"
          else "warning" if resp["data_quality_warnings"] else "ok")
    return to_api(resp, dq)


# ------------------------------------------------------------------ A2
def pen_thermal(body, acfg, now):
    cur = body.current.model_dump(exclude_none=True)
    cur["timestamp_utc"] = cur.pop("timestamp")
    cur.setdefault("amg_summary_c", None)
    cur.setdefault("dht_temp_c", None)
    pen = body.pen_id
    if pen:
        cur["pen_id"] = pen
    dq, w = freshness(body.current.timestamp, now)
    if dq != "ok":
        resp = make_response(PEN_COMPONENT, "unavailable", "statistical", acfg,
                             reasons=[f"Not assessed: {w}."],
                             inputs=[inp("amg_summary_c", cur["amg_summary_c"], "sensor", "degC", cur["timestamp_utc"]),
                                     inp("dht_temp_c", cur["dht_temp_c"], "sensor", "degC", cur["timestamp_utc"])],
                             now=now)
        return to_api(resp, dq)
    hist = []
    for r in body.history:
        d = r.model_dump(exclude_none=True)
        d["timestamp_utc"] = d.pop("timestamp")
        if pen:
            d["pen_id"] = pen
        hist.append(d)
    resp = assess_pen_thermal(cur, hist, cfg=acfg, now=now)
    if resp["status"] == "unavailable":
        offline = "sensor_offline" in (cur.get("amg_summary_c__state"), cur.get("dht_temp_c__state"))
        dq = "offline" if offline else "invalid"
    elif resp["status"] == "insufficient_baseline":
        dq = "insufficient"
    else:
        dq = "warning" if resp["data_quality_warnings"] else "ok"
    return to_api(resp, dq)


# ------------------------------------------------------------------ existing Flutter calls
def flutter_farm(body, acfg, now):
    resp = assess_thi(body.temperature_c, body.humidity_pct, cfg=acfg, now=now)
    ignored = [k for k in ("weight_change_kg", "feed_intake_kg", "medicine_given") if getattr(body, k) is not None]
    warn = ["reading time not supplied by the client; freshness cannot be checked"]
    if ignored:
        warn.append(f"ignored inputs (not used by the THI band): {ignored}")
    api = to_api(resp, "warning", warn)
    recs = acfg["labels"]["recommendations"]
    return {"condition": resp["status_label"], "insights": resp["reasons"],
            "recommendations": recs.get(resp["status"], recs["unavailable"]), "assessment": api}


def flutter_pig(body, acfg):
    return {"classification": None, "insight": acfg["labels"]["compat_pig_insight"], "recommendation": None}
