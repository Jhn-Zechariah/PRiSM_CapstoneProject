"""Phase 1 synthetic data generator.

Produces multi-day 1-minute series with the same columns as the real Firestore
data (pigBodyTemp, ambientTemp, ambientHumidity, sprinkler) plus `source`,
`scenario` and `bias_regime`. It simulates physics, never labels.

    python simulate.py                 # uses config.yaml, writes data/synthetic/synthetic_1min.parquet
    python simulate.py --days 90 --seed 7
"""
from __future__ import annotations

import argparse

import numpy as np
import pandas as pd

from common import PIG, AMB, HUM, SPR, SENSORS, SYNTHETIC_PATH, envelope, load_config
from features import compute_thi
from sanity import envelope_warnings, range_report

MIN_PER_DAY = 1440


def _u(rng, lo_hi):
    return float(rng.uniform(lo_hi[0], lo_hi[1]))


def _ar1(rng, n, sd, phi):
    """Stationary AR(1) noise with marginal standard deviation `sd`."""
    e = rng.normal(0.0, sd * np.sqrt(1 - phi ** 2), n)
    out = np.empty(n)
    out[0] = rng.normal(0.0, sd)
    for i in range(1, n):
        out[i] = phi * out[i - 1] + e[i]
    return out


def _cosine_through(anchor_x, anchor_y, x):
    """Smooth curve through anchors: half-cosine between consecutive points."""
    i = np.clip(np.searchsorted(anchor_x, x, side="right") - 1, 0, len(anchor_x) - 2)
    x0, x1 = anchor_x[i], anchor_x[i + 1]
    y0, y1 = anchor_y[i], anchor_y[i + 1]
    frac = np.clip((x - x0) / (x1 - x0), 0, 1)
    return y0 + (y1 - y0) * (1 - np.cos(np.pi * frac)) / 2


def _smooth(a, minutes):
    return pd.Series(a).rolling(minutes, center=True, min_periods=1).mean().to_numpy()


def sample_days(cfg, rng, days):
    sim = cfg["simulator"]
    names = list(sim["scenario_weights"])
    w = np.array([sim["scenario_weights"][n] for n in names], dtype=float)
    picks = []
    for _ in range(days):
        if picks and rng.random() < sim["scenario_persistence"]:
            picks.append(picks[-1])
        else:
            picks.append(str(rng.choice(names, p=w / w.sum())))
    bias_cfg = sim["amg8833_reading_bias"]
    plan = []
    for d, s in enumerate(picks):
        sc = sim["scenarios"][s]
        if d and s == picks[d - 1]:
            # same weather spell -> same sensor regime, so the reading does not jump at midnight
            regime, base = plan[-1]["bias_regime"], plan[-1]["bias_base"]
        else:
            if sc["bias_regime"] == "paper":
                regime = "paper"
            else:
                regime = "field" if rng.random() < bias_cfg["field_probability"] else "paper"
            base = bias_cfg[f"{regime}_bias"]
            base = _u(rng, base) if isinstance(base, list) else float(base)
        bias = base + rng.normal(0, bias_cfg["day_jitter_sd"])
        plan.append({
            "scenario": s, "t_min": _u(rng, sc["t_min"]), "t_max": _u(rng, sc["t_max"]),
            "t_min_hour": _u(rng, sim["t_min_hour"]), "peak_hour": _u(rng, sim["peak_hour"]),
            "rh_mean": _u(rng, sc["rh_mean"]), "rh_slope": sc["rh_temp_slope"],
            "rh_clip": sc["rh_clip"], "bias_regime": regime, "bias_base": base, "bias": bias,
        })
    return plan


def simulate(cfg: dict | None = None, days: int | None = None, seed: int | None = None) -> pd.DataFrame:
    cfg = cfg or load_config()
    sim = cfg["simulator"]
    days = days or sim["days"]
    rng = np.random.default_rng(cfg["project"]["random_seed"] if seed is None else seed)
    env = envelope(cfg)
    n = days * MIN_PER_DAY
    hours = np.arange(n) / 60.0                     # local hours since start
    day_idx = np.arange(n) // MIN_PER_DAY
    plan = sample_days(cfg, rng, days)

    # ---------------- ambient temperature: daily curve + scenario + noise ----------------
    ax, ay = [], []
    for d, p in enumerate(plan):
        ax += [d * 24 + p["t_min_hour"], d * 24 + p["peak_hour"]]
        ay += [p["t_min"], p["t_max"]]
    ax = np.array([ax[0] - 24] + ax + [ax[-2] + 24])
    ay = np.array([ay[0]] + ay + [ay[-2]])
    amb = _cosine_through(ax, ay, hours)

    rain = np.zeros(n)
    for d, p in enumerate(plan):
        sc = sim["scenarios"][p["scenario"]]
        for _ in range(rng.poisson(sc.get("rain_events_per_day", 0.0))):
            centre = d * MIN_PER_DAY + rng.integers(0, MIN_PER_DAY)
            span = np.arange(n) - centre
            rain += np.exp(-0.5 * (span / rng.uniform(20, 50)) ** 2)
    rain = np.clip(rain, 0, 1.5)
    amb = amb - rain * np.array([sim["scenarios"][plan[d]["scenario"]].get("rain_cooling_c", 0.0)
                                 for d in day_idx])
    amb = amb + _ar1(rng, n, sim["ambient_noise_sd"], sim["ambient_ar"])

    # ---------------- humidity: inverse to temperature, per-day offsets ----------------
    per_min = lambda key: np.array([plan[d][key] for d in day_idx], dtype=float)
    t_mean_day = _smooth(np.array([(plan[d]["t_min"] + plan[d]["t_max"]) / 2 for d in day_idx]), 180)
    rh_mean = _smooth(per_min("rh_mean"), 180)
    rh_slope = _smooth(per_min("rh_slope"), 180)
    rh = rh_mean - rh_slope * (amb - t_mean_day) + 5.0 * rain
    rh = rh + _ar1(rng, n, sim["humidity_noise_sd"], sim["humidity_ar"])
    rh_lo = np.array([plan[d]["rh_clip"][0] for d in day_idx])
    rh_hi = np.array([plan[d]["rh_clip"][1] for d in day_idx])
    rh = np.clip(rh, rh_lo, rh_hi)

    # ---------------- sprinkler events (scheduled + manual) ----------------
    sp = sim["sprinkler"]
    spray = np.zeros(n, dtype=np.int8)

    def run(start):
        length = int(rng.integers(sp["run_minutes"][0], sp["run_minutes"][1] + 1))
        spray[start:start + length] = 1

    for d, p in enumerate(plan):
        if p["scenario"] in sp["schedule_on_scenarios"]:
            for h in sp["schedule_hours"]:
                run(int(d * MIN_PER_DAY + h * 60))
    thi_air = compute_thi(amb, rh)
    hot = thi_air > sp["manual_thi_threshold"]
    manual_starts = hot & (rng.random(n) < sp["manual_rate_per_hour_hot"] / 60.0)
    for i in np.flatnonzero(manual_starts):
        if not spray[i]:
            run(i)
    # DHT22 sees slightly cooler, wetter air during a run
    amb = amb - sp["ambient_drop_c"] * spray
    rh = np.minimum(rh + sp["humidity_rise_pct"] * spray, 100.0)
    amb = np.clip(amb, env[AMB]["min"], env[AMB]["max"])
    rh = np.clip(rh, env[HUM]["min"], min(env[HUM]["max"], 100.0))
    thi = compute_thi(amb, rh)

    # wet-skin cooling: 1 while spraying, fades with wet_decay_tau afterwards
    wet = np.zeros(n)
    decay = np.exp(-1.0 / sp["wet_decay_tau_min"])
    for i in range(1, n):
        wet[i] = 1.0 if spray[i] else wet[i - 1] * decay

    # ---------------- pig surface temperature: lagged first-order response ----------------
    pg = sim["pig"]
    n_pigs = sim["n_pigs"]
    target_common = (pg["base_surface_c"] + pg["ambient_slope"] * (amb - 20.0)
                     + pg["thi_slope"] * np.maximum(0.0, thi - pg["thi_reference"])
                     - sp["spray_effect_c"] * wet)
    baseline = rng.normal(0, pg["per_pig_baseline_sd"], n_pigs)
    indiv = np.stack([_ar1(rng, n, pg["individual_sd"], pg["individual_ar"]) for _ in range(n_pigs)], axis=1)
    target = target_common[:, None] + baseline[None, :] + indiv
    alpha = 1 - np.exp(-1.0 / pg["response_tau_min"])
    surf = np.empty((n, n_pigs))
    surf[0] = target[0]
    for i in range(1, n):
        surf[i] = surf[i - 1] + alpha * (target[i] - surf[i - 1])
    true_pen = np.clip(surf.max(axis=1), *pg["true_clip"])   # AMG8833 = hottest pixel = hottest pig

    bias = _smooth(np.array([plan[d]["bias"] for d in day_idx]), 240)
    pig = true_pen - bias

    # pig out of the camera's view: hottest pixel falls towards air temperature
    ov = sim["out_of_view"]
    away = np.zeros(n)
    for d in range(days):
        if plan[d]["bias_regime"] != "field":
            continue
        for _ in range(rng.poisson(ov["episodes_per_day"])):
            s = d * MIN_PER_DAY + int(rng.integers(0, MIN_PER_DAY))
            away[s:s + int(rng.integers(ov["minutes"][0], ov["minutes"][1] + 1))] = 1.0
    away = _smooth(away, 3)
    floor = amb + rng.uniform(*ov["offset_above_ambient_c"])
    pig = np.where(away > 0, (1 - away) * pig + away * np.minimum(floor, pig), pig)
    pig = np.clip(pig, env[PIG]["min"], env[PIG]["max"])

    # ---------------- sensor imperfections ----------------
    se = sim["sensor"]
    drift_step = se["drift_sd_per_day"] / np.sqrt(MIN_PER_DAY)
    readings = {}
    for var, clean, sd in ((PIG, pig, se["pig_noise_sd"]), (AMB, amb, se["ambient_noise_sd"]),
                           (HUM, rh, se["humidity_noise_sd"])):
        drift = np.cumsum(rng.normal(0, drift_step, n))
        val = clean + drift + rng.normal(0, sd, n)
        spikes = rng.random(n) < se["spike_probability"]
        val[spikes] += rng.choice([-1, 1], spikes.sum()) * rng.uniform(*se["spike_magnitude"], spikes.sum())
        readings[var] = val
    readings[HUM] = np.clip(readings[HUM], 0, 100)

    missing = np.zeros(n, dtype=bool)
    for d in range(days):
        for _ in range(rng.poisson(se["gaps_per_day"])):
            s = d * MIN_PER_DAY + int(rng.integers(0, MIN_PER_DAY))
            missing[s:s + int(rng.integers(se["gap_minutes"][0], se["gap_minutes"][1] + 1))] = True
    for var in SENSORS:
        readings[var][missing] = np.nan

    tz = cfg["project"]["timezone"]
    local = pd.date_range(pd.Timestamp(sim["start_date"], tz=tz), periods=n, freq="1min")
    df = pd.DataFrame({
        "timestamp": local.tz_convert("UTC"),
        PIG: np.round(readings[PIG], 2),
        AMB: np.round(readings[AMB], 2),
        HUM: np.round(readings[HUM], 2),
        SPR: spray,
        "source": "synthetic",
        "scenario": [plan[d]["scenario"] for d in day_idx],
        "bias_regime": [plan[d]["bias_regime"] for d in day_idx],
    })
    return df


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--days", type=int)
    ap.add_argument("--seed", type=int)
    ap.add_argument("--out", default=str(SYNTHETIC_PATH))
    a = ap.parse_args()
    cfg = load_config()
    df = simulate(cfg, a.days, a.seed)
    from pathlib import Path
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    df.to_parquet(a.out, index=False)
    days = len(df) // MIN_PER_DAY
    print(f"Wrote {len(df):,} rows ({days} days) -> {a.out}")
    print("Scenario mix (days):", (df.groupby("scenario").size() // MIN_PER_DAY).to_dict())
    print("Bias regime (days):", (df.groupby("bias_regime").size() // MIN_PER_DAY).to_dict())
    rep = range_report(df, cfg)
    for var, r in rep["per_sensor"].items():
        print(f"  {var:16s} normal {r['pct_in_normal_band']:6.2f}%  observed {r['pct_in_observed_band']:6.2f}%"
              f"  envelope {r['pct_in_training_envelope']:6.2f}%")
    envelope_warnings(rep, cfg)


if __name__ == "__main__":
    main()
