"""Optional, DISPLAY-ONLY commercial benchmark (pic_2019_commercial_benchmark.csv).

Only rows whose `use` column equals the configured value ("context_only") are loaded.
Weights are linearly interpolated between listed ages; there is no extrapolation
outside the listed age range. Nothing in this module is used to raise a flag or set
a status (see growth.py: flags are computed before the benchmark is looked up).
"""
import csv
from pathlib import Path

from assess.config import resolve_path


def load_benchmark(bcfg, path=None):
    """Returns (rows or None, warnings). rows = sorted [(age_days, weight_kg)]."""
    p = Path(path) if path is not None else resolve_path(bcfg["path"])
    if not p.is_file():
        return None, []
    cols, want = bcfg["columns"], bcfg["required_use"]
    rows, skipped = [], 0
    with open(p, newline="", encoding="utf-8") as f:
        for line in csv.DictReader(f):
            if (line.get(cols["use"]) or "").strip() != want:
                skipped += 1
                continue
            try:
                rows.append((float(line[cols["age_days"]]), float(line[cols["weight_kg"]])))
            except (KeyError, TypeError, ValueError):
                skipped += 1
    warnings = [f"benchmark: ignored {skipped} row(s) not marked use={want} or unreadable"] if skipped else []
    rows.sort()
    if len(rows) < 2:
        return None, warnings + ["benchmark: fewer than two usable rows; not shown"]
    return rows, warnings


def benchmark_weight(rows, age_days):
    """Interpolated benchmark weight, or None outside the listed ages."""
    if rows is None or age_days is None or not rows[0][0] <= age_days <= rows[-1][0]:
        return None
    for (a0, w0), (a1, w1) in zip(rows, rows[1:]):
        if a0 <= age_days <= a1:
            return w0 if a1 == a0 else w0 + (w1 - w0) * (age_days - a0) / (a1 - a0)
    return None


def benchmark_context(rows, age_days, weight_kg, labels):
    """The display block attached to a growth response."""
    ref = benchmark_weight(rows, age_days)
    if ref is None:
        reason = "benchmark file not present" if rows is None else (
            f"age {age_days} d outside benchmark ages {rows[0][0]:g}-{rows[-1][0]:g} d")
        return {"shown": False, "message": labels["no_reference"], "reason": reason}, None
    return {"shown": True, "label": labels["benchmark_label"], "age_days": age_days,
            "benchmark_weight_kg": round(ref, 2),
            "pct_of_benchmark": round(weight_kg / ref * 100.0, 1)}, "context_only"
