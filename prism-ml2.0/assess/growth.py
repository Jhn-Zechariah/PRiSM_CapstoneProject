"""A1: growth-trend monitoring from the pig's OWN manual weigh-ins.

No external curve is used for any flag. Pigs are never labelled Normal / Underweight /
Overweight. The optional commercial benchmark is attached afterwards for display only.

Inputs
  pig:     {"pig_id", "birth_date", "sex", "breed", "pen_id" (optional; PRISM has no pen field yet)}
  weights: [{"date", "weight_kg", "source" (optional), "notes" (optional), "id" (optional)}]
           Firestore: pigs/{pigId}/weight_history -> weightKg, dateRecorded, notes
"""
from statistics import median

from assess.benchmark import benchmark_context, load_benchmark
from assess.config import load
from assess.response import inp, make_response
from pipeline.normalize import parse_time

COMPONENT = "growth_trend"
REQUIRED = ("min_weighins", "min_interval_days")


def _span_adg(points):
    """Time-weighted ADG (g/day) from first to last of a list of (date, kg)."""
    days = (points[-1][0] - points[0][0]).total_seconds() / 86400.0
    return (points[-1][1] - points[0][1]) / days * 1000.0 if days > 0 else None


def _clean(weights, g):
    """Drops unusable weigh-ins (with a warning each). Returns sorted [(date, kg, id)]."""
    keep, warnings, inferred = [], [], 0
    for w in weights:
        wid = w.get("id") or str(w.get("date"))
        src = w.get("source")
        if src is None:
            inferred += 1
        elif src not in g["accepted_sources"]:
            warnings.append(f"weigh-in {wid} ignored: source {src!r} is not manual (weights are never sensor data)")
            continue
        if (w.get("notes") or "") in g["exclude_records_with_notes"]:
            warnings.append(f"weigh-in {wid} ignored: notes {w.get('notes')!r} are excluded by config")
            continue
        dt = parse_time(w.get("date"))[0]
        kg = w.get("weight_kg")
        if dt is None or not isinstance(kg, (int, float)) or isinstance(kg, bool) or kg <= 0:
            warnings.append(f"weigh-in {wid} ignored: missing/invalid date or weight")
            continue
        keep.append((dt, float(kg), wid))
    if inferred:
        warnings.append(f"{inferred} weigh-in(s) have no source field; treated as manual")
    keep.sort()
    return keep, warnings


def _space(points, min_days, warnings):
    """Keeps the latest weigh-in, then walks back keeping one only if it is at least
    min_days before the last kept one. Dropped weigh-ins are reported."""
    kept = []
    for p in reversed(points):
        if not kept or (kept[-1][0] - p[0]).total_seconds() / 86400.0 >= min_days:
            kept.append(p)
        else:
            warnings.append(f"weigh-in {p[2]} not used: less than {min_days} d before the next used weigh-in")
    return list(reversed(kept))


def _flags(intervals, g):
    """The three configured rules. Uses ONLY the pig's own intervals."""
    flags, reasons = [], []
    last = intervals[-1]

    if g["weight_loss_min_kg"] is None:
        reasons.append("weight-loss rule not configured")
    elif last["gain_kg"] < 0 and -last["gain_kg"] >= g["weight_loss_min_kg"]:
        flags.append("weight_loss")
        reasons.append(f"Weight fell {-last['gain_kg']:.2f} kg between {last['from']} and {last['to']} "
                       f"(rule: loss >= {g['weight_loss_min_kg']} kg).")

    n, cap = g["stall_consecutive_intervals"], g["stall_adg_max_g_per_day"]
    if n is None or cap is None:
        reasons.append("stalled-gain rule not configured")
    elif len(intervals) >= n and all(iv["adg_g_per_day"] <= cap for iv in intervals[-n:]):
        flags.append("stalled_gain")
        reasons.append(f"ADG was at or below {cap} g/day for the last {n} interval(s): "
                       + ", ".join(f"{iv['adg_g_per_day']:.0f}" for iv in intervals[-n:]) + ".")

    pct, need = g["relative_drop_pct"], g["relative_drop_min_prior_intervals"]
    if pct is None or need is None:
        reasons.append("relative-drop rule not configured")
    elif len(intervals) - 1 < need:
        reasons.append(f"relative-drop rule needs {need} earlier interval(s); have {len(intervals) - 1}")
    else:
        prior = _span_adg([(intervals[0]["_t0"], intervals[0]["_w0"]),
                           (intervals[-2]["_t1"], intervals[-2]["_w1"])])
        if prior is None or prior <= 0:
            reasons.append("relative-drop rule not evaluated: earlier average ADG is not positive")
        elif last["adg_g_per_day"] < prior * (1 - pct / 100.0):
            flags.append("relative_drop")
            reasons.append(f"Latest ADG {last['adg_g_per_day']:.0f} g/day is more than {pct}% below "
                           f"this pig's earlier average {prior:.0f} g/day.")
    return flags, reasons


def assess_growth(pig, weights, cfg=None, now=None, benchmark_path=None):
    cfg = cfg or load()
    g = cfg["assessment"]["growth"]
    labels = cfg["labels"]
    birth = parse_time(pig.get("birth_date"))[0]

    points, warnings = _clean(weights or [], g)
    inputs = [inp("birth_date", birth.date().isoformat() if birth else None, "manual"),
              inp("sex", pig.get("sex"), "manual"),
              inp("breed", pig.get("breed"), "manual")]
    inputs += [inp("weight_kg", kg, "manual", "kg", dt) for dt, kg, _ in points]
    details = {"pig_id": pig.get("pig_id"), "pen_id": pig.get("pen_id"), "intervals": [],
               "rolling_adg_g_per_day": None, "latest_adg_g_per_day": None, "flags": []}

    def respond(status, reasons, reference_type=None):
        return make_response(COMPONENT, status, "rule", cfg, reasons, inputs, warnings,
                             details=details, reference_type=reference_type, now=now)

    missing = [k for k in REQUIRED if g[k] is None]
    if missing:
        return respond("not_configured", [f"Set {', '.join(missing)} in config/assessment.json."])

    used = _space(points, g["min_interval_days"], warnings)
    if len(used) < g["min_weighins"]:
        return respond("insufficient_data", [
            f"Needs at least {g['min_weighins']} weigh-ins at least {g['min_interval_days']} day(s) apart; "
            f"have {len(used)} usable."])

    intervals = []
    for (t0, w0, _), (t1, w1, _) in zip(used, used[1:]):
        days = (t1 - t0).total_seconds() / 86400.0
        intervals.append({"from": t0.date().isoformat(), "to": t1.date().isoformat(),
                          "days": round(days, 2), "gain_kg": round(w1 - w0, 3),
                          "adg_g_per_day": (w1 - w0) / days * 1000.0,
                          "_t0": t0, "_w0": w0, "_t1": t1, "_w1": w1})

    flags, reasons = _flags(intervals, g)          # <- no benchmark data reaches this call

    k = g["rolling_window_intervals"]
    if k is None:
        warnings.append("rolling ADG not computed: rolling_window_intervals not configured")
    else:
        win = intervals[-k:]
        details["rolling_adg_g_per_day"] = round(_span_adg([(win[0]["_t0"], win[0]["_w0"]),
                                                            (win[-1]["_t1"], win[-1]["_w1"])]), 1)
        details["rolling_window_intervals"] = len(win)
    details["latest_adg_g_per_day"] = round(intervals[-1]["adg_g_per_day"], 1)
    details["intervals"] = [{k2: (round(v, 1) if k2 == "adg_g_per_day" else v)
                             for k2, v in iv.items() if not k2.startswith("_")} for iv in intervals]
    details["flags"] = [{"flag": f, "message": labels["flags"][f]} for f in flags]
    status = "flags_raised" if flags else "no_flags"

    # ---- display-only benchmark, attached AFTER status and flags are final ----
    latest_t, latest_w, _ = used[-1]
    age = (latest_t - birth).days if birth else None
    details["age_days_at_latest_weighin"] = age
    rows, bwarn = load_benchmark(g["benchmark"], benchmark_path)
    warnings.extend(bwarn)
    details["benchmark"], ref_type = benchmark_context(rows, age, latest_w, labels)
    return respond(status, reasons, ref_type)


def add_pen_comparison(responses, cfg=None):
    """Adds details.pen_comparison to growth responses of pigs that share a pen_id.
    Uses rolling ADG (latest ADG if rolling is not configured). Never changes status."""
    cfg = cfg or load()
    min_pigs = cfg["assessment"]["growth"]["pen_comparison_min_pigs"]
    note = cfg["labels"]["pen_comparison_note"]
    out = [dict(r, details=dict(r["details"])) for r in responses]
    pens = {}
    for r in out:
        d = r["details"]
        basis = "rolling" if d.get("rolling_adg_g_per_day") is not None else "latest"
        adg = d.get(f"{basis}_adg_g_per_day")
        if d.get("pen_id") and adg is not None:
            pens.setdefault(d["pen_id"], []).append((r, adg, basis))
    for pen, members in pens.items():
        if len(members) < min_pigs:
            continue
        med = median(a for _, a, _ in members)
        for r, adg, basis in members:
            r["details"]["pen_comparison"] = {
                "pen_id": pen, "pigs_in_comparison": len(members),
                "pen_median_adg_g_per_day": round(med, 1),
                "adg_g_per_day": adg, "adg_basis": basis,
                "difference_g_per_day": round(adg - med, 1),
                "pct_of_pen_median": round(adg / med * 100.0, 1) if med > 0 else None,
                "note": note}
    return out
