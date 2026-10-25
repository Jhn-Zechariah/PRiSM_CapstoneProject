"""B1: rule-based THI risk band from DHT22 air temperature and relative humidity.

Band i+1 is entered when THI >= thresholds[i] (rises are immediate, so heat risk is
never delayed). With a previous band supplied, the band only drops once THI is below
(threshold - hysteresis), so small changes around a threshold do not make it flip.
"""
from assess.config import compile_formula, load
from assess.response import inp, make_response
from pipeline.normalize import parse_time

COMPONENT = "thi_band"


def compute_thi(temperature_c, humidity_pct, cfg):
    f = cfg["assessment"]["thi"]["formula"]
    return compile_formula(f["expression"], f["variables"])(T=temperature_c, RH=humidity_pct)


def _check_category(c, n_bands):
    thr, hys = c.get("thresholds"), c.get("hysteresis")
    if thr is None or hys is None:
        return None
    if len(thr) != n_bands - 1 or any(b <= a for a, b in zip(thr, thr[1:])):
        raise ValueError(f"thresholds must be {n_bands - 1} strictly ascending values, got {thr}")
    if hys < 0:
        raise ValueError("hysteresis must be >= 0")
    return thr, hys


def band_index(thi, thresholds, hysteresis, previous=None):
    """Returns (index, held). held=True when hysteresis kept a higher band."""
    raw = sum(thi >= t for t in thresholds)
    if previous is None or raw >= previous:
        return raw, False
    kept = sum(thi >= t - hysteresis for t in thresholds)
    band = min(previous, max(raw, kept))
    return band, band > raw


def assess_thi(temperature_c, humidity_pct, category=None, previous_band=None,
               observed_at=None, quality_flags=(), cfg=None, now=None):
    """previous_band: band key from the last assessment of this pen (for hysteresis).
    quality_flags: flags from pipeline.validate for this reading, if available."""
    cfg = cfg or load()
    tcfg = cfg["assessment"]["thi"]
    keys = tcfg["band_keys"]
    observed = parse_time(observed_at)[0] if observed_at is not None else None
    category = category or tcfg["default_category"]

    inputs = [inp("dht_temp_c", temperature_c, "sensor", "degC", observed),
              inp("dht_humidity_pct", humidity_pct, "sensor", "%RH", observed),
              inp("pig_category", category, "manual")]
    cwarn = []
    if tcfg["formula"].get("status") == "placeholder_pending_confirmation":
        cwarn.append("THI formula is a placeholder pending confirmation: " + tcfg["formula"]["expression"])
    details = {"category": category, "thi": None, "formula": tcfg["formula"]["expression"]}

    def respond(status, reasons, warnings=()):
        return make_response(COMPONENT, status, "rule", cfg, reasons, inputs, warnings, cwarn, details, now=now)

    # ---- data checks: missing, physically impossible, flagged upstream ----
    warnings = [f for f in quality_flags if "dht_" in f or f.split(":")[0] in
                ("stale_timestamp", "missing_timestamp", "duplicate")]
    bad = [f for f in warnings if cfg["validation"]["severity"].get(f.split(":")[0]) == "bad"]
    if temperature_c is None or humidity_pct is None:
        return respond("insufficient_data", ["DHT22 temperature and humidity are both required."], warnings)
    vch = cfg["validation"]["channels"]
    for name, v in (("dht_temp_c", temperature_c), ("dht_humidity_pct", humidity_pct)):
        lo, hi = vch[name]["impossible"]
        if not lo <= v <= hi:
            return respond("unavailable", [f"{name}={v} is outside the possible range {lo}..{hi}."],
                           warnings + [f"impossible:{name}"])
    if bad:
        return respond("unavailable", ["The reading failed data-quality checks: " + ", ".join(bad)], warnings)

    thi = compute_thi(temperature_c, humidity_pct, cfg)
    details["thi"] = round(thi, 2)

    cat = tcfg["categories"].get(category)
    if cat is None:
        return respond("not_configured", [f"No THI settings for pig category {category!r}."], warnings)
    checked = _check_category(cat, len(keys))
    if checked is None:
        return respond("not_configured",
                       [f"THI thresholds/hysteresis for {category!r} are not set in config/assessment.json."],
                       warnings)
    thresholds, hysteresis = checked
    details.update(thresholds=thresholds, hysteresis=hysteresis)

    prev_idx = None
    if previous_band is not None:
        if previous_band in keys:
            prev_idx = keys.index(previous_band)
        else:
            warnings.append(f"previous_band {previous_band!r} unknown; hysteresis not applied")
    idx, held = band_index(thi, thresholds, hysteresis, prev_idx)
    details.update(previous_band=previous_band, raw_band=keys[sum(thi >= t for t in thresholds)],
                   held_by_hysteresis=held)

    labels = cfg["labels"]["status"]
    if held:
        t = thresholds[idx - 1]
        reasons = [f"THI {thi:.1f} is below {t} but not below {t - hysteresis:.1f} "
                   f"(threshold minus hysteresis {hysteresis}), so the band stays {labels[keys[idx]]}."]
    elif idx == 0:
        reasons = [f"THI {thi:.1f} is below {thresholds[0]}."]
    else:
        nxt = f" and below {thresholds[idx]}" if idx < len(thresholds) else ""
        reasons = [f"THI {thi:.1f} is at or above {thresholds[idx - 1]}{nxt}."]
    return respond(keys[idx], reasons, warnings)
