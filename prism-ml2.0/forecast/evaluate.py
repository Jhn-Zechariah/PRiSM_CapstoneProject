"""Splits, models, tuning, single test evaluation, bootstrap CIs, alerts, error analysis."""
import math

import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingRegressor, RandomForestRegressor
from sklearn.impute import SimpleImputer
from sklearn.linear_model import Ridge
from sklearn.model_selection import ParameterGrid
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.tree import DecisionTreeRegressor

NO_FIT = ("persistence", "same_time_yesterday")


# ------------------------------------------------------------------ splits
def make_splits(frame, fcfg, horizon):
    """Rolling-origin folds inside the development period + one untouched test period.
    Training rows always end `gap` before the rows they are scored on (gap >= horizon)."""
    s, tz = fcfg["splits"], fcfg["timezone"]
    times = frame["time"]
    gap = pd.Timedelta(minutes=max(horizon, s["min_gap_minutes"]))
    last_date = times.max().tz_convert(tz).normalize()
    test_start = (last_date - pd.Timedelta(days=s["test_days"] - 1)).tz_convert("UTC")
    dev_end = test_start - gap
    folds = []
    for j in range(s["n_folds"]):
        val_start = dev_end - pd.Timedelta(days=s["val_days"] * (s["n_folds"] - j))
        val_end = val_start + pd.Timedelta(days=s["val_days"])
        train = (times < val_start - gap).to_numpy()
        val = ((times >= val_start) & (times < val_end)).to_numpy()
        span = (val_start - gap - times.min()) / pd.Timedelta(days=1)
        folds.append({"train": train, "val": val, "val_start": val_start, "val_end": val_end,
                      "train_end": val_start - gap, "train_span_days": round(float(span), 2),
                      "n_train": int(train.sum()), "n_val": int(val.sum())})
    split = {"gap": gap, "test_start": test_start, "dev_end": dev_end,
             "dev": (times < dev_end).to_numpy(), "test": (times >= test_start).to_numpy(), "folds": folds}
    problems = [f"fold {i}: train span {f['train_span_days']} d < {s['min_train_days']} d"
                for i, f in enumerate(folds) if f["train_span_days"] < s["min_train_days"]]
    problems += [f"fold {i}: empty train or validation set" for i, f in enumerate(folds)
                 if not f["n_train"] or not f["n_val"]]
    if not split["test"].any():
        problems.append("empty test period")
    split["problems"] = problems
    return split


# ------------------------------------------------------------------ models
def make_model(name, params, seed):
    imp = ("impute", SimpleImputer(strategy="median", keep_empty_features=True))
    if name == "ridge":
        return Pipeline([imp, ("scale", StandardScaler()), ("model", Ridge(**params))])
    if name == "decision_tree":
        return Pipeline([imp, ("model", DecisionTreeRegressor(random_state=seed, **params))])
    if name == "random_forest":
        return Pipeline([imp, ("model", RandomForestRegressor(random_state=seed, n_jobs=-1, **params))])
    if name == "gradient_boosting":
        return Pipeline([imp, ("model", HistGradientBoostingRegressor(random_state=seed, early_stopping=False,
                                                                       **params))])
    raise ValueError(f"unknown model {name}")


def to_level(pred, frame, fcfg):
    return frame["current"].to_numpy() + pred if fcfg["predict"] == "delta" else pred


def fit_predict(name, params, train, score, features, fcfg):
    """Fits on `train` rows only (imputer/scaler included) and returns LEVEL predictions for `score`."""
    if name == "persistence":
        return score["current"].to_numpy(dtype=float)
    if name == "same_time_yesterday":
        return score["yday"].to_numpy(dtype=float)
    m = make_model(name, params, fcfg["seed"])
    m.fit(train[features].to_numpy(dtype=float), train["y"].to_numpy(dtype=float))
    return to_level(m.predict(score[features].to_numpy(dtype=float)), score, fcfg)


def mae(y, p):
    return float(np.mean(np.abs(y - p)))


def rmse(y, p):
    return float(np.sqrt(np.mean((y - p) ** 2)))


def tune(frame, split, features, fcfg):
    """Validation-fold MAE for every model and grid point. Test rows are never touched."""
    grids = fcfg["models"]["grids"]
    names = fcfg["models"]["baselines"] + fcfg["models"]["candidates"]
    table, best = {}, {}
    for name in names:
        rows = []
        for params in (ParameterGrid(grids[name]) if name in grids else [{}]):
            scores = []
            for f in split["folds"]:
                tr, va = frame[f["train"]], frame[f["val"]]
                scores.append(mae(va["y_level"].to_numpy(), fit_predict(name, params, tr, va, features, fcfg)))
            rows.append({"params": dict(params), "fold_mae": [round(x, 4) for x in scores],
                         "mean_val_mae": float(np.mean(scores))})
        table[name] = rows
        best[name] = min(rows, key=lambda r: r["mean_val_mae"])          # first wins ties (grid order)
    return table, best


# ------------------------------------------------------------------ bootstrap over days
def day_index(test):
    days = sorted(test["local_date"].unique())
    code = test["local_date"].map({d: i for i, d in enumerate(days)}).to_numpy()
    return code, len(days)


def resample_matrix(n_days, fcfg):
    b = fcfg["bootstrap"]
    rng = np.random.default_rng(fcfg["seed"])
    return rng.integers(0, n_days, size=(b["n_resamples"], n_days))


def _per_day(values, code, n_days):
    return np.bincount(code, weights=values, minlength=n_days)


def _ci(samples, fcfg):
    a = (100 - fcfg["bootstrap"]["ci_pct"]) / 2
    samples = np.asarray(samples, dtype=float)
    samples = samples[np.isfinite(samples)]
    if not len(samples):
        return None
    return [round(float(np.percentile(samples, a)), 4), round(float(np.percentile(samples, 100 - a)), 4)]


def error_stats(y, preds, base_name, code, n_days, R, fcfg):
    """MAE/RMSE with day-block CIs, plus each model's difference vs `base_name`."""
    cnt = _per_day(np.ones_like(y), code, n_days)[R].sum(axis=1)
    out = {}
    sums = {}
    for name, p in preds.items():
        ae, se = np.abs(y - p), (y - p) ** 2
        sa, ss = _per_day(ae, code, n_days), _per_day(se, code, n_days)
        sums[name] = (sa, ss)
        out[name] = {"mae": round(mae(y, p), 4), "rmse": round(rmse(y, p), 4),
                     "mae_ci": _ci(sa[R].sum(axis=1) / cnt, fcfg),
                     "rmse_ci": _ci(np.sqrt(ss[R].sum(axis=1) / cnt), fcfg)}
    ba, bs = sums[base_name]
    for name, (sa, ss) in sums.items():
        d_mae = (sa[R].sum(axis=1) - ba[R].sum(axis=1)) / cnt
        d_rmse = np.sqrt(ss[R].sum(axis=1) / cnt) - np.sqrt(bs[R].sum(axis=1) / cnt)
        out[name]["vs_best_baseline"] = {
            "baseline": base_name,
            "mae_diff": round(out[name]["mae"] - out[base_name]["mae"], 4), "mae_diff_ci": _ci(d_mae, fcfg),
            "rmse_diff": round(out[name]["rmse"] - out[base_name]["rmse"], 4), "rmse_diff_ci": _ci(d_rmse, fcfg)}
    return out


# ------------------------------------------------------------------ alerts
def _prf(tp, fp, fn):
    precision = tp / (tp + fp) if tp + fp else None
    recall = tp / (tp + fn) if tp + fn else None
    f1 = (2 * tp / (2 * tp + fp + fn)) if (2 * tp + fp + fn) else None
    return precision, recall, f1


def alert_metrics(test, preds, thr, grid, horizon, code, n_days, R, fcfg):
    """Event at t: THI is below thr now and a MEASURED value in (t, t+h] reaches thr.
    Predicted at t: below thr now and the point forecast for t+h is >= thr."""
    below = (test["current"] < thr).to_numpy()
    known = test["fut_max"].notna().to_numpy()
    rows = below & known
    actual = (test["fut_max"] >= thr).to_numpy() & rows
    test_days = n_days
    # crossing events in the measured series during the test period
    events = []
    t0 = test["time"].min()
    for pen, g in grid.groupby("pen"):
        g = g.sort_values("time")
        crossed = (g["thi"] >= thr) & (g["thi"].shift(1) < thr) & (g["time"] >= t0)
        events += [(pen, t) for t in g.loc[crossed, "time"]]
    out = {"threshold": thr, "rows_evaluated": int(rows.sum()), "actual_events_rows": int(actual.sum()),
           "crossing_events_in_test": len(events), "test_days": test_days,
           "definition": "rows where THI < threshold at t; actual = any measured THI in (t, t+h] >= threshold; "
                         "predicted = forecast for t+h >= threshold"}
    models = {}
    for name, p in preds.items():
        pred = (p >= thr) & rows
        tp, fp = int((pred & actual).sum()), int((pred & ~actual & rows).sum())
        fn, tn = int((~pred & actual).sum()), int((~pred & ~actual & rows).sum())
        precision, recall, f1 = _prf(tp, fp, fn)
        dtp = _per_day((pred & actual).astype(float), code, n_days)[R].sum(axis=1)
        dfp = _per_day((pred & ~actual & rows).astype(float), code, n_days)[R].sum(axis=1)
        dfn = _per_day((~pred & actual).astype(float), code, n_days)[R].sum(axis=1)
        denom = 2 * dtp + dfp + dfn
        f1_s = np.where(denom > 0, 2 * dtp / np.where(denom > 0, denom, 1), np.nan)
        rec_d = dtp + dfn
        rec_s = np.where(rec_d > 0, dtp / np.where(rec_d > 0, rec_d, 1), np.nan)
        # alert onsets (False -> True) per pen, per test day
        flag = pd.Series(pred, index=test.index)
        prev = flag.groupby(test["pen"]).shift(1, fill_value=False)
        onsets = int((flag & ~prev).sum())
        # lead time: earliest predicted alert within the horizon before each crossing
        leads = []
        pt = test.loc[pred, ["pen", "time"]]
        for pen, c in events:
            w = pt[(pt["pen"] == pen) & (pt["time"] >= c - pd.Timedelta(minutes=horizon)) & (pt["time"] < c)]
            if len(w):
                leads.append((c - w["time"].min()) / pd.Timedelta(minutes=1))
        models[name] = {
            "confusion_matrix": {"tn": tn, "fp": fp, "fn": fn, "tp": tp},
            "precision": None if precision is None else round(precision, 4),
            "recall": None if recall is None else round(recall, 4),
            "f1": None if f1 is None else round(f1, 4),
            "f1_ci": _ci(f1_s, fcfg), "recall_ci": _ci(rec_s, fcfg),
            "alerts_per_day": round(onsets / test_days, 3) if test_days else None,
            "events_detected_before_crossing": len(leads),
            "median_lead_minutes": float(np.median(leads)) if leads else None,
            "mean_lead_minutes": round(float(np.mean(leads)), 1) if leads else None}
    for name in models:
        base = models.get("persistence", {}).get("median_lead_minutes") or 0.0
        own = models[name]["median_lead_minutes"]
        models[name]["lead_time_gained_vs_persistence_minutes"] = None if own is None else own - base
    out["models"] = models
    return out


# ------------------------------------------------------------------ error analysis
def _group_mae(y, preds, groups):
    out = {}
    for g in sorted(pd.unique(groups), key=str):
        m = groups == g
        out[str(g)] = {"n": int(m.sum()), **{n: round(mae(y[m], p[m]), 4) for n, p in preds.items()}}
    return out


def error_analysis(dev, test, preds, fcfg):
    e = fcfg["error_analysis"]
    y = test["y_level"].to_numpy()
    hb = e["hour_bucket_hours"]
    hours = (test["local_hour"] // hb * hb).astype(int)
    hour_lbl = hours.map(lambda x: f"{x:02d}-{x + hb:02d}h").to_numpy()
    q = e["condition_quantiles"]

    def tercile(col):
        cuts = dev[col].quantile(q).to_numpy()
        v = test[col].to_numpy()
        lbl = np.where(np.isnan(v), "unknown",
                       np.where(v < cuts[0], f"low (<{cuts[0]:.1f})",
                                np.where(v < cuts[1], f"mid ({cuts[0]:.1f}-{cuts[1]:.1f})", f"high (>={cuts[1]:.1f})")))
        return lbl

    mist = test["mist_now"]
    mist_lbl = np.where(mist.isna(), "not logged", np.where(mist > 0, "misting on", "misting off"))
    return {
        "by_time_of_day_local": _group_mae(y, preds, hour_lbl),
        "by_pen_air_temperature": _group_mae(y, preds, tercile("temp_now")),
        "by_pen_humidity": _group_mae(y, preds, tercile("hum_now")),
        "by_recent_sensor_fault": _group_mae(y, preds, np.where(test["fault_recent"], "fault in last window",
                                                                "no fault")),
        "by_misting_state": _group_mae(y, preds, mist_lbl),
        "note": "'weather' uses pen conditions measured by the DHT22 (terciles from development data); "
                "no external weather data is logged in PRISM.",
    }


def hottest_hours_mae(dev, test, preds, fcfg):
    k = fcfg["hottest_hours"]["k"]
    hours = dev.groupby("target_local_hour")["y_level"].mean().sort_values(ascending=False).index[:k]
    m = test["target_local_hour"].isin(hours).to_numpy()
    y = test["y_level"].to_numpy()
    return {"hours_local": sorted(int(h) for h in hours), "n": int(m.sum()),
            "mae": {n: (round(mae(y[m], p[m]), 4) if m.any() else None) for n, p in preds.items()}}


def held_out_pen(frame, split, features, best, fcfg):
    pens = sorted(frame["pen"].unique())
    if len(pens) < 2:
        return {"possible": False, "reason": f"only {len(pens)} pen in the data"}
    out = {"possible": True, "pens": {}}
    dev, test = frame[split["dev"]], frame[split["test"]]
    for p in pens:
        tr, te = dev[dev["pen"] != p], test[test["pen"] == p]
        if not len(tr) or not len(te):
            out["pens"][p] = {"n_test": int(len(te)), "skipped": "no rows"}
            continue
        y = te["y_level"].to_numpy()
        out["pens"][p] = {"n_test": int(len(te)), **{
            n: round(mae(y, fit_predict(n, best[n]["params"], tr, te, features, fcfg)), 4) for n in best}}
    out["note"] = "models trained on the other pens' development data, scored on the held-out pen's test period"
    return out
