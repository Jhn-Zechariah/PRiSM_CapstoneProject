"""Describe exported real data to support recalibrating the risk cutoffs.

    python analyze_real_data.py

Prints percentiles of pig surface temperature and of the gap (pig surface minus
ambient), the share of readings above each placeholder cutoff, and the range
report. It only RECOMMENDS; it never changes config.yaml.
"""
from __future__ import annotations

import json

import numpy as np

from common import AMB, PIG, REPORTS_DIR, load_config
from datasets import load_real_frame
from sanity import envelope_warnings, range_report

PCTS = [1, 5, 10, 25, 50, 75, 90, 95, 97.5, 99]


def main():
    cfg = load_config()
    frame = load_real_frame(cfg)
    if frame is None:
        raise SystemExit("No real data found. Run export_firestore.py first.")
    rows = frame[~frame["missing"]]
    pig = rows[PIG].dropna()
    gap = (rows[PIG] - rows[AMB]).dropna()
    days = sorted(set(rows.index.tz_convert(cfg["project"]["timezone"]).strftime("%Y-%m-%d")))
    print(f"Real data: {len(rows):,} usable minutes over {len(days)} days ({days[0]} .. {days[-1]})\n")

    pct = lambda s: {str(p): round(float(np.percentile(s, p)), 2) for p in PCTS}
    out = {"usable_minutes": int(len(rows)), "days": days,
           "pigBodyTemp_percentiles": pct(pig), "gap_pig_minus_ambient_percentiles": pct(gap)}
    print("pigBodyTemp percentiles:", out["pigBodyTemp_percentiles"])
    print("gap (pig - ambient) percentiles:", out["gap_pig_minus_ambient_percentiles"])

    r = cfg["risk"]
    above = {f"> needs_attention_above ({r['needs_attention_above']} C)": float((pig > r["needs_attention_above"]).mean()),
             f">= high_risk_at ({r['high_risk_at']} C)": float((pig >= r["high_risk_at"]).mean())}
    out["pct_above_cutoffs"] = {k: round(100 * v, 3) for k, v in above.items()}
    print("\nShare of real readings above the current (placeholder) cutoffs:")
    for k, v in out["pct_above_cutoffs"].items():
        print(f"  {k}: {v}%")

    rep = range_report(rows, cfg)
    rep.pop("bands")
    out["range_report"] = rep
    print("\nRange report (% of valid readings):")
    for var, s in rep["per_sensor"].items():
        print(f"  {var:16s} normal {s['pct_in_normal_band']}%  observed {s['pct_in_observed_band']}%  "
              f"envelope {s['pct_in_training_envelope']}%")
    out["warnings"] = envelope_warnings(rep, cfg)

    print("\nFOR DISCUSSION ONLY (config.yaml is not changed):")
    print("  The literature cutoffs assume a 34-37 C normal band. If the AMG8833 keeps reading lower,")
    print("  consider sensor-relative cutoffs, e.g. Needs Attention above the real P90 "
          f"({out['pigBodyTemp_percentiles']['90']} C) and High Risk at the real P97.5 "
          f"({out['pigBodyTemp_percentiles']['97.5']} C), or a gap-based rule using the gap percentiles,")
    print("  validated against a reference thermometer or observed pig behaviour before adoption.")

    REPORTS_DIR.mkdir(exist_ok=True)
    path = REPORTS_DIR / "real_data_analysis.json"
    path.write_text(json.dumps(out, indent=2))
    print(f"\nSaved {path}")


if __name__ == "__main__":
    main()
