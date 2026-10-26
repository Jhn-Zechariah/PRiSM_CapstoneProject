"""Evaluate a trained forecaster.

    python evaluate.py --data synthetic             # test split of synthetic days
    python evaluate.py --data real                  # frozen real hold-out block
    python evaluate.py --data transfer              # synthetic-trained model on ALL real data

Reports MAE/RMSE at t+15 and t+30 vs the persistence baseline, risk-class accuracy
and per-class recall after mapping to Good / Needs Attention / High Risk, early-warning
lead time, noon-peak vs rest-of-day error, error by hour, and plots.
"""
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd

from common import CURRENT_MODEL_PATH, PIG, REPORTS_DIR, load_config
import model_io
from risk import LEVELS, risk_levels

SYNTHETIC_DISCLAIMER = ("SYNTHETIC-DATA RESULTS: pipeline sanity check only. These numbers come from "
                        "simulated data and are NOT the accuracy of the real PRISM system.")
REAL_NOTE = "Real-data results on the frozen hold-out block (never used for training)."

# reference palette (dataviz skill, light mode): neutral ink for actuals, slots 1-2 for horizons
INK, MUTED, GRID = "#0b0b0b", "#8a8984", "#e4e3df"
H_COLORS = {15: "#2a78d6", 30: "#eb6834"}


def predictions_frame(bundle: dict, sup: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    preds = model_io.predict(bundle, sup)
    df = pd.DataFrame(index=sup.index)
    df["current"] = sup[PIG].to_numpy()
    for h, p in preds.items():
        df[f"pred_{h}"] = p
        df[f"actual_{h}"] = sup[f"actual_{h}"].to_numpy()
    df["day"] = sup["day"].to_numpy() if "day" in sup else ""
    df["hour"] = sup.index.tz_convert(cfg["project"]["timezone"]).hour
    return df


def _mae(e):
    return float(np.mean(np.abs(e))) if len(e) else float("nan")


def _rmse(e):
    return float(np.sqrt(np.mean(np.square(e)))) if len(e) else float("nan")


def regression_metrics(p: pd.DataFrame, horizons) -> dict:
    out = {}
    for h in horizons:
        err = p[f"pred_{h}"] - p[f"actual_{h}"]
        base = p["current"] - p[f"actual_{h}"]
        mae, bmae = _mae(err), _mae(base)
        out[f"t+{h}"] = {"mae": round(mae, 4), "rmse": round(_rmse(err), 4),
                         "baseline_persistence_mae": round(bmae, 4),
                         "baseline_persistence_rmse": round(_rmse(base), 4),
                         "mae_skill_vs_baseline": round(1 - mae / bmae, 4) if bmae else None}
    return out


def _class_report(true, pred) -> dict:
    true, pred = np.asarray(true), np.asarray(pred)
    rep = {"accuracy": round(float((true == pred).mean()), 4) if len(true) else None, "per_class": {}}
    for c in LEVELS:
        m = true == c
        rep["per_class"][c] = {"support": int(m.sum()),
                               "recall": round(float((pred[m] == c).mean()), 4) if m.any() else None,
                               "predicted": int((pred == c).sum())}
    rep["confusion_matrix"] = {"labels": LEVELS, "rows_true_cols_pred": [
        [int(((true == a) & (pred == b)).sum()) for b in LEVELS] for a in LEVELS]}
    return rep


def risk_metrics(p: pd.DataFrame, horizons, cfg) -> dict:
    out = {}
    for h in horizons:
        out[f"t+{h}"] = _class_report(risk_levels(p[f"actual_{h}"], cfg), risk_levels(p[f"pred_{h}"], cfg))
    # what the app shows: the worse of the two horizons
    act = np.max([p[f"actual_{h}"] for h in horizons], axis=0)
    pre = np.max([p[f"pred_{h}"] for h in horizons], axis=0)
    out["app_level_max_of_horizons"] = _class_report(risk_levels(act, cfg), risk_levels(pre, cfg))
    return out


def lead_times(p: pd.DataFrame, horizons, cfg, thr: float | None = None) -> dict:
    """Early-warning lead time for each sustained crossing above `thr` (default: needs_attention_above).

    An event is a minute c where the actual temperature, smoothed with a trailing
    `lead_time_smooth_min` rolling mean, rises above the threshold after staying below it for
    `lead_time_quiet_min`, and then stays above for `lead_time_sustain_min` (so sensor noise
    and single spikes are not events). Lead time = minutes the model's flag (any horizon's
    forecast above the threshold) had been continuously raised right before c, capped at
    `lead_time_max_min`. 0 = no advance warning.
    """
    ev = cfg["evaluation"]
    thr = cfg["risk"]["needs_attention_above"] if thr is None else thr
    full = pd.date_range(p.index.min(), p.index.max(), freq="1min")
    cur = p["current"].reindex(full).rolling(ev["lead_time_smooth_min"], min_periods=ev["lead_time_smooth_min"]).mean()
    flag = (p[[f"pred_{h}" for h in horizons]].max(axis=1) > thr).reindex(full, fill_value=False).astype(bool)
    above = (cur > thr).to_numpy()
    quiet, sustain = ev["lead_time_quiet_min"], ev["lead_time_sustain_min"]
    leads = []
    for i in np.flatnonzero(above):
        if i < quiet or i + sustain > len(cur):
            continue
        before, after = cur.iloc[i - quiet:i], cur.iloc[i:i + sustain]
        if before.isna().any() or (before > thr).any() or after.isna().any() or not (after > thr).all():
            continue
        lead = 0
        for j in range(i - 1, max(-1, i - 1 - ev["lead_time_max_min"]), -1):
            if flag.iloc[j]:
                lead += 1
            else:
                break
        leads.append(lead)
    leads = np.array(leads)
    if not len(leads):
        return {"n_events": 0, "note": "no sustained crossings into the stress band in this data"}
    return {"n_events": int(len(leads)), "median_min": float(np.median(leads)), "mean_min": round(float(leads.mean()), 2),
            "pct_with_any_warning": round(100 * float((leads > 0).mean()), 2),
            "pct_with_15min_or_more": round(100 * float((leads >= 15).mean()), 2),
            "leads_min": leads.tolist(), "threshold_c": thr}


def peak_vs_rest(p: pd.DataFrame, horizons, cfg) -> dict:
    lo, hi = cfg["evaluation"]["noon_peak_hours"]
    # error at the time being forecast (t+h), so use the target's local hour
    out = {}
    for h in horizons:
        target_hour = (p.index + pd.Timedelta(minutes=h)).tz_convert(cfg["project"]["timezone"]).hour
        peak = (target_hour >= lo) & (target_hour < hi)
        err = (p[f"pred_{h}"] - p[f"actual_{h}"]).to_numpy()
        out[f"t+{h}"] = {"noon_peak_mae": round(_mae(err[peak]), 4), "rest_of_day_mae": round(_mae(err[~peak]), 4),
                         "noon_peak_hours_local": [lo, hi]}
    return out


def error_by_hour(p: pd.DataFrame, horizons) -> dict:
    return {f"t+{h}": {int(k): round(float(v), 4) for k, v in
                       (p[f"pred_{h}"] - p[f"actual_{h}"]).abs().groupby(p["hour"]).mean().items()}
            for h in horizons}


def feature_importance(bundle: dict, top: int = 20) -> dict:
    out = {}
    cols = bundle["feature_columns"]
    for h, est in bundle["estimators"].items():
        if est is None:
            continue
        model = est[-1] if hasattr(est, "steps") else est
        if hasattr(model, "feature_importances_"):
            imp = np.asarray(model.feature_importances_, dtype=float)
        elif hasattr(model, "coef_"):
            imp = np.abs(np.ravel(model.coef_))     # standardised inputs -> comparable magnitudes
        else:
            continue
        imp = imp / imp.sum() if imp.sum() else imp
        order = np.argsort(imp)[::-1][:top]
        out[f"t+{h}"] = {cols[i]: round(float(imp[i]), 4) for i in order}
    return out


# ----------------------------------------------------------------------------- plots
def _style(ax):
    ax.grid(True, color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    for s in ("left", "bottom"):
        ax.spines[s].set_color(MUTED)
    ax.tick_params(colors=MUTED, labelcolor=INK, labelsize=8)


def make_plots(p: pd.DataFrame, bundle: dict, horizons, cfg, prefix: Path, title_tag: str) -> list[str]:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.dates as mdates
    import matplotlib.pyplot as plt

    tz = cfg["project"]["timezone"]
    files = []

    # 1) predicted vs actual over the hottest day in the evaluation set
    day = p.groupby("day")["current"].max().idxmax()
    d = p[p["day"] == day]
    fig, ax = plt.subplots(figsize=(10, 4))
    ax.plot(d.index.tz_convert(tz), d["current"], color=INK, linewidth=1.6, label="Actual AMG8833 reading")
    for h in horizons:
        ax.plot((d.index + pd.Timedelta(minutes=h)).tz_convert(tz), d[f"pred_{h}"], color=H_COLORS.get(h),
                linewidth=1.2, label=f"Forecast made {h} min earlier")
    for name, y in (("Needs Attention >", cfg["risk"]["needs_attention_above"]),
                    ("High Risk >=", cfg["risk"]["high_risk_at"])):
        ax.axhline(y, color=MUTED, linewidth=0.8, linestyle="--")
        ax.text(d.index.tz_convert(tz)[0], y + 0.05, f"{name} {y} C", color=MUTED, fontsize=7, va="bottom",
                bbox=dict(facecolor="white", edgecolor="none", pad=1))
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M", tz=d.index.tz_convert(tz).tz))
    ax.set_ylabel("Pig surface temperature (C)", color=INK, fontsize=9)
    ax.set_title(f"{title_tag}: forecast vs actual, {day} (hottest day in set)", color=INK, fontsize=10, loc="left")
    ax.legend(frameon=False, fontsize=8, loc="lower left")
    _style(ax)
    fig.tight_layout()
    f = f"{prefix}_day.png"
    fig.savefig(f, dpi=140)
    plt.close(fig)
    files.append(f)

    # 2) error by hour of day
    eb = error_by_hour(p, horizons)
    hours = np.arange(24)
    fig, ax = plt.subplots(figsize=(10, 3.6))
    width = 0.4
    for k, h in enumerate(horizons):
        vals = [eb[f"t+{h}"].get(int(x), np.nan) for x in hours]
        ax.bar(hours + (k - 0.5) * width, vals, width=width - 0.04, color=H_COLORS.get(h), label=f"t+{h} min")
    ax.set_xticks(hours)
    ax.set_xlabel("Local hour of day (when the forecast is made)", color=INK, fontsize=9)
    ax.set_ylabel("MAE (C)", color=INK, fontsize=9)
    ax.set_title(f"{title_tag}: forecast error by hour", color=INK, fontsize=10, loc="left")
    ax.legend(frameon=False, fontsize=8)
    _style(ax)
    fig.tight_layout()
    f = f"{prefix}_error_by_hour.png"
    fig.savefig(f, dpi=140)
    plt.close(fig)
    files.append(f)

    # 3) feature importance (t+30 model)
    fi = feature_importance(bundle, top=15)
    key = f"t+{max(horizons)}"
    if key in fi:
        items = list(fi[key].items())[::-1]
        fig, ax = plt.subplots(figsize=(7, 5))
        ax.barh([k for k, _ in items], [v for _, v in items], color=H_COLORS.get(max(horizons)), height=0.7)
        ax.set_xlabel("Relative importance", color=INK, fontsize=9)
        ax.set_title(f"{title_tag}: top features, {bundle['model_name']} t+{max(horizons)}",
                     color=INK, fontsize=10, loc="left")
        _style(ax)
        fig.tight_layout()
        f = f"{prefix}_feature_importance.png"
        fig.savefig(f, dpi=140)
        plt.close(fig)
        files.append(f)
    return files


def evaluate(bundle: dict, sup: pd.DataFrame, cfg: dict, data_label: str,
             plot_prefix: Path | None = None) -> dict:
    horizons = cfg["features"]["horizons_min"]
    p = predictions_frame(bundle, sup, cfg)
    res = {
        "data": data_label,
        "disclaimer": SYNTHETIC_DISCLAIMER if "synthetic" in data_label else REAL_NOTE,
        "n_rows": int(len(p)), "days": sorted(set(p["day"])),
        "regression": regression_metrics(p, horizons),
        "risk_classification": risk_metrics(p, horizons, cfg),
        "early_warning_lead_time": {
            "into_needs_attention": lead_times(p, horizons, cfg, cfg["risk"]["needs_attention_above"]),
            "into_high_risk": lead_times(p, horizons, cfg, cfg["risk"]["high_risk_at"]),
        },
        "noon_peak_vs_rest": peak_vs_rest(p, horizons, cfg),
        "error_by_hour": error_by_hour(p, horizons),
        "risk_cutoffs_used": {"needs_attention_above": cfg["risk"]["needs_attention_above"],
                              "high_risk_at": cfg["risk"]["high_risk_at"], "status": "PLACEHOLDER"},
    }
    if plot_prefix is not None and len(p):
        tag = "SYNTHETIC" if "synthetic" in data_label else "REAL"
        res["plots"] = [str(Path(f).relative_to(REPORTS_DIR.parent)) for f in
                        make_plots(p, bundle, horizons, cfg, plot_prefix, tag)]
    return res


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", default=str(CURRENT_MODEL_PATH))
    ap.add_argument("--data", choices=["synthetic", "real", "transfer"], required=True)
    a = ap.parse_args()
    cfg = load_config()
    bundle = model_io.load(a.model)
    from datasets import build_splits, load_real_frame, supervised
    if a.data == "transfer":
        frame = load_real_frame(cfg)
        if frame is None:
            raise SystemExit("No real data exported yet.")
        sup = supervised(frame, cfg)
        label = "synthetic-to-real transfer (all real data)"
    else:
        sup = build_splits(a.data, cfg)["test"]
        label = f"{a.data} test"
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d")
    REPORTS_DIR.mkdir(exist_ok=True)
    prefix = REPORTS_DIR / f"eval_{a.data}_{stamp}"
    res = evaluate(bundle, sup, cfg, label, prefix)
    res["model"] = {k: bundle.get(k) for k in ("model_name", "version", "data_source", "trained_at")}
    out = REPORTS_DIR / f"metrics_eval_{a.data}_{stamp}.json"
    out.write_text(json.dumps(res, indent=2, default=str))
    print(json.dumps({k: res[k] for k in ("data", "disclaimer", "regression")}, indent=2))
    print(f"Saved {out}")


if __name__ == "__main__":
    main()
