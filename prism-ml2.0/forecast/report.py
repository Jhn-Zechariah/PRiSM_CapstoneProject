"""Acceptance rule, plain-language conclusions, JSON + Markdown report."""
import json
from pathlib import Path

VALID = "VALID: real logged data"
INVALID = "PIPELINE TEST ONLY, NOT VALID RESULTS"
PLACEHOLDER = "<"


def conclusions(horizons):
    """Plain statements computed from the numbers; nothing is hard-coded."""
    lines, any_beat = [], False
    for h, r in horizons.items():
        if r.get("status") != "completed":
            lines.append(f"{h} min: not evaluated ({r.get('reason')}).")
            continue
        b = r["best_baseline"]
        beat = [c for c in r["candidates"]
                if (ci := r["test"][c]["vs_best_baseline"]["mae_diff_ci"]) and ci[1] < 0]
        any_beat |= bool(beat)
        c = r["best_candidate"]
        t = r["test"][c]
        d = t["vs_best_baseline"]
        lines.append(
            f"{h} min: best candidate (chosen on validation) {c} test MAE {t['mae']} vs best baseline "
            f"(chosen on validation) {b} test MAE {r['test'][b]['mae']}; difference {d['mae_diff']} "
            f"(95% CI {d['mae_diff_ci']}). Lower MAE than the best baseline: "
            f"{'yes' if d['mae_diff'] < 0 else 'no'}. Candidates whose MAE-difference CI is entirely "
            f"below zero: {', '.join(beat) if beat else 'none'}.")
    return lines, any_beat


def apply_acceptance(rule, horizons, synthetic):
    if synthetic:
        return {"allowed": False, "reason": "synthetic data: pipeline test only, no model may be enabled"}
    if rule is None:
        return {"allowed": False, "reason": "no acceptance_rule in config/forecast.json; the team must set it "
                                            "before results are seen, so no model may be enabled"}
    bad = [k for k in ("set_by", "set_on", "horizon_minutes", "metric", "compare_to")
           if rule.get(k) is None or str(rule.get(k)).startswith(PLACEHOLDER)]
    if bad:
        return {"allowed": False, "reason": f"acceptance_rule incomplete: {bad}"}
    h = str(rule["horizon_minutes"])
    r = horizons.get(h)
    if not r or r.get("status") != "completed":
        return {"allowed": False, "reason": f"horizon {h} was not evaluated"}
    metric = rule["metric"]
    cand = r["best_candidate"]
    base = r["best_baseline"] if rule["compare_to"] == "best_baseline" else rule["compare_to"]
    if base not in r["test"] or metric not in ("mae", "rmse"):
        return {"allowed": False, "reason": f"unknown compare_to {base!r} or metric {metric!r}"}
    cv, bv = r["test"][cand][metric], r["test"][base][metric]
    checks = []
    if rule.get("min_improvement_pct") is not None:
        imp = (bv - cv) / bv * 100 if bv else float("-inf")
        checks.append({"check": f"{metric} improvement >= {rule['min_improvement_pct']}%",
                       "value": round(imp, 2), "pass": imp >= rule["min_improvement_pct"]})
    if rule.get("require_ci_excludes_zero"):
        if base == r["best_baseline"]:
            ci = r["test"][cand]["vs_best_baseline"][f"{metric}_diff_ci"]
            checks.append({"check": f"95% CI of {metric} difference entirely below 0", "value": ci,
                           "pass": bool(ci) and ci[1] < 0})
        else:
            checks.append({"check": "CI vs a non-best baseline", "value": None, "pass": False,
                           "note": "CIs are computed against the best baseline only"})
    alerts = (r.get("alerts") or {}).get("models", {}).get(cand)
    for key, field, ok in (("min_alert_recall", "recall", lambda v, x: v is not None and v >= x),
                           ("max_alerts_per_day", "alerts_per_day", lambda v, x: v is not None and v <= x)):
        if rule.get(key) is not None:
            v = alerts.get(field) if alerts else None
            checks.append({"check": f"{field} vs {key}={rule[key]}", "value": v, "pass": ok(v, rule[key])})
    if not checks:
        return {"allowed": False, "reason": "acceptance_rule has no criteria filled in", "rule": rule}
    allowed = all(c["pass"] for c in checks)
    return {"allowed": allowed, "candidate": cand, "horizon_minutes": int(h), "compared_to": base,
            "checks": checks, "rule": rule,
            "reason": "all acceptance checks passed" if allowed else "one or more acceptance checks failed"}


def _fmt(v):
    return "–" if v is None else (f"[{v[0]}, {v[1]}]" if isinstance(v, list) else str(v))


def to_markdown(rep):
    tag = rep["validity"]
    L = [f"# B2 forecasting experiment: {tag}", ""]
    if tag == INVALID:
        L += ["> **PIPELINE TEST ONLY, NOT VALID RESULTS.** Built from synthetic fixtures to check that the "
              "code runs. Do not cite any number below.", ""]
    L += [f"- Status: **{rep['status']}**", f"- Dataset version: `{rep['dataset_version']}`",
          f"- Config: `{rep['config_version']}` (sha256 {rep['config_sha256'][:12]})",
          f"- Seed: {rep['seed']}; target: {rep['target']} ({rep['predict']}); horizons: {rep['horizons_minutes']} min",
          f"- Software: {rep['software']}", ""]
    s = rep["sufficiency"]
    L += [f"## Data ({tag})", "",
          f"- Independent days (≥ {s['min_day_coverage_pct']}% usable target bins): **{s['independent_days']}** "
          f"(required {s['required_independent_days']})",
          f"- Data summary: `{json.dumps(rep['data_summary'])}`", ""]
    if rep.get("stop"):
        L += ["## Stopped", "", rep["stop"]["message"], "", "What is needed:", ""]
        L += [f"- {x}" for x in rep["stop"]["needed"]] + [""]
    if rep.get("conclusions"):
        L += [f"## Conclusion ({tag})", ""] + [f"- {x}" for x in rep["conclusions"]]
        L += ["", f"Any candidate beat the best baseline (MAE-difference CI below zero) at any horizon: "
                  f"**{'yes' if rep['any_candidate_beat_best_baseline'] else 'no'}**", ""]
    a = rep.get("acceptance")
    if a:
        L += [f"## Acceptance ({tag})", "", f"- Allowed to enable: **{'yes' if a['allowed'] else 'no'}**: {a['reason']}"]
        for c in a.get("checks", []):
            L.append(f"  - {c['check']}: {_fmt(c['value'])}: {'pass' if c['pass'] else 'FAIL'}")
        L.append("")
    for h, r in rep.get("horizons", {}).items():
        L += [f"## Horizon {h} min ({tag})", ""]
        if r.get("status") != "completed":
            L += [f"Not evaluated: {r.get('reason')}", ""]
            continue
        L += [f"- Rows: dev {r['n_dev']}, test {r['n_test']}; independent test days {r['test_days']}; "
              f"gap {r['gap_minutes']} min; test period from {r['test_start']}",
              f"- Best baseline (validation): {r['best_baseline']}; best candidate (validation): {r['best_candidate']}",
              "", "| model | chosen params | mean val MAE | test MAE [95% CI] | test RMSE [95% CI] | "
                  "MAE − best baseline [95% CI] | hottest-hours MAE |", "|---|---|---|---|---|---|---|"]
        for m, t in r["test"].items():
            d = t["vs_best_baseline"]
            L.append(f"| {m} | `{json.dumps(r['chosen_params'][m])}` | {round(r['val_mae'][m], 4)} | "
                     f"{t['mae']} {_fmt(t['mae_ci'])} | {t['rmse']} {_fmt(t['rmse_ci'])} | "
                     f"{d['mae_diff']} {_fmt(d['mae_diff_ci'])} | {_fmt(r['hottest_hours']['mae'][m])} |")
        L += ["", f"Hottest hours (local, from training data): {r['hottest_hours']['hours_local']}", ""]
        al = r.get("alerts")
        if al and "models" in al:
            L += [f"Alert (THI ≥ {al['threshold']} within {h} min): {al['definition']}. "
                  f"Crossing events in test: {al['crossing_events_in_test']}.", "",
                  "| model | TN | FP | FN | TP | precision | recall [CI] | F1 [CI] | alerts/day | median lead min | lead gained vs persistence |",
                  "|---|---|---|---|---|---|---|---|---|---|---|"]
            for m, x in al["models"].items():
                cm = x["confusion_matrix"]
                L.append(f"| {m} | {cm['tn']} | {cm['fp']} | {cm['fn']} | {cm['tp']} | {_fmt(x['precision'])} | "
                         f"{_fmt(x['recall'])} {_fmt(x['recall_ci'])} | {_fmt(x['f1'])} {_fmt(x['f1_ci'])} | "
                         f"{_fmt(x['alerts_per_day'])} | {_fmt(x['median_lead_minutes'])} | "
                         f"{_fmt(x['lead_time_gained_vs_persistence_minutes'])} |")
            L.append("")
        else:
            L += [f"Alert metrics: {al.get('reason') if al else 'not computed'}", ""]
        ea = r["error_analysis"]
        show = [r["best_baseline"], r["best_candidate"], "persistence"]
        show = list(dict.fromkeys(show))
        L += ["Error analysis (test MAE): " + ea["note"], ""]
        for k, groups in ea.items():
            if k == "note":
                continue
            L += [f"*{k}*", "", "| group | n | " + " | ".join(show) + " |", "|---|---|" + "---|" * len(show)]
            for g, v in groups.items():
                L.append(f"| {g} | {v['n']} | " + " | ".join(str(v[m]) for m in show) + " |")
            L.append("")
        hp = r["held_out_pen"]
        L += [f"Held-out pen: {json.dumps(hp)}", ""]
    L += ["## Features", "", ", ".join(rep.get("features", [])) or "–", ""]
    return "\n".join(L)


def write(rep, out_dir):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    (out / "report.json").write_text(json.dumps(rep, indent=2, default=str), encoding="utf-8")
    (out / "report.md").write_text(to_markdown(rep), encoding="utf-8")
    return out
