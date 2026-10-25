"""A2: statistical PEN-LEVEL thermal flag from the AMG8833 summary, adjusted for ambient.

The AMG8833 cannot tell pigs apart, so this is about the pen, never a specific pig, and
never a body/core temperature. A reading is compared with a rolling robust baseline
(median and MAD) built only from EARLIER readings of the same pen whose DHT22 ambient
temperature fell in the same bin (optionally also the same time-of-day block).

Records use the pipeline's canonical fields (pipeline.normalize / pipeline.validate):
  timestamp_utc (or effective_time_utc), amg_summary_c, dht_temp_c, pen_id/device_key,
  and optionally quality + <channel>__state from validation.
"""
import math
from datetime import timedelta
from statistics import median

from assess.config import load
from assess.response import inp, make_response
from pipeline.normalize import parse_time

COMPONENT = "pen_thermal"


def _time(rec):
    v = rec.get("effective_time_utc") or rec.get("timestamp_utc")
    return parse_time(v)[0] if v is not None else None


def _num(v):
    return float(v) if isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) else None


def _problems(rec, p):
    """Why a record cannot be used (empty list = usable)."""
    out = []
    for f in (p["summary_field"], p["ambient_field"]):
        if _num(rec.get(f)) is None:
            out.append(f"{f} missing")
        elif rec.get(f"{f}__state", "normal") != "normal":
            out.append(f"{f} state={rec[f'{f}__state']}")
    if rec.get("quality") == "bad":
        out.append("record quality=bad")
    if _time(rec) is None:
        out.append("no usable timestamp")
    return out


def _bin(ambient, p):
    i = math.floor((ambient - p["bin_origin_c"]) / p["bin_width_c"])
    lo = p["bin_origin_c"] + i * p["bin_width_c"]
    return i, lo, lo + p["bin_width_c"]


def _block(t, p):
    h = p["time_of_day_block_hours"]
    return None if h is None else int(t.hour // h)


def _pen(rec):
    return rec.get("pen_id") or rec.get("device_key")


def assess_pen_thermal(current, history, cfg=None, now=None):
    cfg = cfg or load()
    p = cfg["assessment"]["pen_thermal"]
    labels = cfg["labels"]
    sf, af = p["summary_field"], p["ambient_field"]
    t0 = _time(current)
    inputs = [inp(sf, current.get(sf), "sensor", "degC", t0),
              inp(af, current.get(af), "sensor", "degC", t0),
              inp("time_of_day_utc", t0.strftime("%H:%M") if t0 else None, "sensor")]
    cwarn = ([f"pen_thermal settings are defaults pending review ({p['status']})"]
             if p.get("status") == "default_pending_review" else [])
    details = {"pen": _pen(current)}
    warnings = []

    def respond(status, reasons):
        return make_response(COMPONENT, status, "statistical", cfg, reasons, inputs, warnings, cwarn,
                             details, now=now)

    probs = _problems(current, p)
    if probs:
        warnings.extend(probs)
        return respond("unavailable", ["Current reading cannot be assessed: " + "; ".join(probs) + "."])

    x, amb = float(current[sf]), float(current[af])
    b, lo, hi = _bin(amb, p)
    blk = _block(t0, p)
    start = t0 - timedelta(days=p["window_days"])
    pen = _pen(current)

    base, skipped = [], 0
    for r in history:
        t = _time(r)
        if t is None or not (start <= t < t0):
            continue
        if pen is not None and _pen(r) is not None and _pen(r) != pen:
            continue
        if _problems(r, p):
            skipped += 1
            continue
        if _bin(float(r[af]), p)[0] != b or _block(t, p) != blk:
            continue
        base.append(float(r[sf]))
    if skipped:
        warnings.append(f"{skipped} earlier reading(s) excluded from the baseline by data-quality checks")

    cond = f"ambient {lo:g} to {hi:g} degC" + (
        "" if blk is None else f", time block {blk} ({blk * p['time_of_day_block_hours']}:00 UTC onward)")
    details.update(ambient_bin_c=[lo, hi], time_block=blk, window_days=p["window_days"],
                   baseline_n=len(base), baseline_required=p["min_baseline_samples"])
    if len(base) < p["min_baseline_samples"]:
        return respond("insufficient_baseline", [
            f"Baseline has {len(base)} reading(s) for {cond} in the previous {p['window_days']} day(s); "
            f"needs {p['min_baseline_samples']} ({p['min_baseline_samples'] - len(base)} more)."])

    med = median(base)
    mad = median(abs(v - med) for v in base)
    sd = max(p["mad_scale"] * mad, p["mad_floor_c"])
    z = (x - med) / sd
    thr = p["robust_z_threshold"]
    unusual = {"high": z > thr, "low": z < -thr, "both": abs(z) > thr}[p["flag_direction"]]
    details.update(baseline_median_c=round(med, 3), baseline_mad_c=round(mad, 3),
                   robust_sd_c=round(sd, 3), robust_z=round(z, 2), z_threshold=thr,
                   flag_direction=p["flag_direction"])
    reasons = [f"Pen summary {x:g} degC vs baseline median {med:.2f} degC for {cond} "
               f"(robust z = {z:.2f}, threshold {thr}, n = {len(base)})."]
    if unusual:
        details["message"] = labels["pen_thermal_message"]
        return respond("unusual", [labels["pen_thermal_message"]] + reasons)
    return respond("typical", reasons)
