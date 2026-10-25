"""Tests for the B2 forecasting experiment. ALL DATA HERE IS SYNTHETIC (pipeline tests only)."""
import copy
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np
import pandas as pd

from assess import config as acfg_mod
from forecast import evaluate as ev
from forecast.data import is_synthetic, load_export, to_grid
from forecast.features import build_frame
from forecast.report import INVALID, apply_acceptance
from forecast.run import load_config, pipeline_test_configs, run_experiment
from pipeline.export import export, read_jsonl
from tests.fixtures.synthetic_forecast import generate

FIX = Path(__file__).resolve().parent / "fixtures"
FCFG = load_config()
ACFG = pipeline_test_configs(acfg_mod.load(), FCFG)          # SYNTHETIC alert threshold 80


def synthetic_grid(days=3, pens=("SYN-p1",), seed=0):
    """SYNTHETIC regular 5-min grid."""
    rng = np.random.default_rng(seed)
    frames = []
    for pen in pens:
        t = pd.date_range("2026-08-01T00:00:00Z", periods=days * 288, freq="5min")
        temp = 27 + 3 * np.sin(np.arange(len(t)) / 288 * 2 * np.pi) + rng.normal(0, 0.1, len(t))
        hum = 85 - 2 * (temp - 27)
        frames.append(pd.DataFrame({"pen": pen, "time": t, "temp": temp, "hum": hum,
                                    "thi": (1.8 * temp + 32) - (0.55 - 0.0055 * hum) * (1.8 * temp - 26),
                                    "n_records": 1, "n_fault": 0, "mist_on": 0.0, "mist_active_s": 0.0}))
    return pd.concat(frames, ignore_index=True)


def small_cfg():
    c = copy.deepcopy(FCFG)
    c["horizons_minutes"] = [30]
    c["models"]["grids"] = {"ridge": {"alpha": [1.0]}, "decision_tree": {"max_depth": [3], "min_samples_leaf": [20]},
                            "random_forest": {"n_estimators": [10], "max_depth": [4], "min_samples_leaf": [20]},
                            "gradient_boosting": {"learning_rate": [0.1], "max_depth": [3], "max_iter": [20]}}
    c["bootstrap"]["n_resamples"] = 50
    return c


class NoLeakage(unittest.TestCase):
    def test_features_do_not_change_when_the_future_changes(self):
        g = synthetic_grid()
        cut = g["time"].iloc[400]
        f1, names = build_frame(g, FCFG, 60)
        g2 = g.copy()
        g2.loc[g2["time"] > cut, ["temp", "hum", "thi"]] += 50.0      # rewrite the future
        f2, _ = build_frame(g2, FCFG, 60)
        a = f1[f1["time"] <= cut].set_index("time")[names]
        b = f2[f2["time"] <= cut].set_index("time")[names]
        pd.testing.assert_frame_equal(a, b)
        self.assertFalse(np.allclose(f1[f1["time"] == cut]["y_level"], f2[f2["time"] == cut]["y_level"]))

    def test_no_identifier_features(self):
        _, names = build_frame(synthetic_grid(pens=("SYN-a", "SYN-b")), FCFG, 30)
        self.assertFalse([n for n in names if "pen" in n or "device" in n or "id" == n])

    def test_target_and_baselines_are_aligned(self):
        g = synthetic_grid()
        f, _ = build_frame(g, FCFG, 60)
        s = g.set_index("time")["thi"]
        row = f.iloc[100]
        self.assertAlmostEqual(row["y_level"], s[row["time"] + pd.Timedelta(minutes=60)])
        self.assertAlmostEqual(row["yday"], s[row["time"] + pd.Timedelta(minutes=60) - pd.Timedelta(days=1)])
        self.assertAlmostEqual(row["current"], s[row["time"]])
        self.assertAlmostEqual(row["y"], row["y_level"] - row["current"])           # predict = delta


class Splits(unittest.TestCase):
    def test_gap_at_least_horizon_and_test_untouched(self):
        g = synthetic_grid(days=40)
        for h in (30, 120):
            f, _ = build_frame(g, FCFG, h)
            sp = ev.make_splits(f, FCFG, h)
            self.assertEqual(sp["problems"], [])
            self.assertGreaterEqual(sp["gap"], pd.Timedelta(minutes=h))
            dev_last = f["time"][sp["dev"]].max()
            self.assertLessEqual(dev_last + pd.Timedelta(minutes=h), sp["test_start"])   # dev targets precede test
            self.assertFalse((sp["dev"] & sp["test"]).any())
            for fold in sp["folds"]:
                tr_last = f["time"][fold["train"]].max()
                self.assertLessEqual(tr_last + pd.Timedelta(minutes=h), fold["val_start"])
                self.assertFalse((fold["val"] & sp["test"]).any())
            local = f["time"][sp["test"]].dt.tz_convert(FCFG["timezone"]).dt.date
            self.assertEqual(local.nunique(), FCFG["splits"]["test_days"])

    def test_too_little_data_reports_problems(self):
        f, _ = build_frame(synthetic_grid(days=10), FCFG, 30)
        self.assertTrue(ev.make_splits(f, FCFG, 30)["problems"])


class ModelsFitInsideFolds(unittest.TestCase):
    def test_imputer_and_scaler_learn_from_training_rows_only(self):
        m = ev.make_model("ridge", {"alpha": 1.0}, 0)
        self.assertEqual([s for s, _ in m.steps], ["impute", "scale", "model"])
        X_train = np.array([[1.0], [np.nan], [3.0]])
        m.fit(X_train, np.array([1.0, 2.0, 3.0]))
        self.assertEqual(m.named_steps["impute"].statistics_[0], 2.0)        # median of train only
        self.assertAlmostEqual(m.named_steps["scale"].mean_[0], 2.0)
        for name in ("decision_tree", "random_forest", "gradient_boosting"):
            self.assertEqual(ev.make_model(name, {}, 0).steps[0][0], "impute")

    def test_baselines(self):
        f = pd.DataFrame({"current": [1.0, 2.0], "yday": [5.0, 6.0]})
        self.assertEqual(list(ev.fit_predict("persistence", {}, None, f, [], FCFG)), [1.0, 2.0])
        self.assertEqual(list(ev.fit_predict("same_time_yesterday", {}, None, f, [], FCFG)), [5.0, 6.0])


class AlertsAndBootstrap(unittest.TestCase):
    def test_alert_metrics_hand_computed(self):
        t = pd.date_range("2026-08-01T00:00:00Z", periods=6, freq="5min")
        test = pd.DataFrame({"pen": "SYN", "time": t, "local_date": "2026-08-01",
                             "current": [70, 70, 70, 70, 85, 70.0],
                             "fut_max": [71, 81, 81, 72, 90, 71.0]})
        grid = pd.DataFrame({"pen": "SYN", "time": t, "thi": [70, 70, 79, 81, 85, 70.0]})
        preds = {"m": np.array([70, 82, 79, 81, 90, 70.0])}
        code, n = ev.day_index(test)
        R = ev.resample_matrix(n, FCFG)
        out = ev.alert_metrics(test, preds, 80.0, grid, 10, code, n, R, FCFG)
        x = out["models"]["m"]
        # rows with current < 80: idx 0,1,2,3,5. actual: 1,2. predicted: 1,3.
        self.assertEqual(x["confusion_matrix"], {"tn": 2, "fp": 1, "fn": 1, "tp": 1})
        self.assertEqual((x["precision"], x["recall"], x["f1"]), (0.5, 0.5, 0.5))
        self.assertEqual(out["crossing_events_in_test"], 1)                  # 79 -> 81 at idx 3
        self.assertEqual(x["median_lead_minutes"], 10.0)                     # predicted at idx 1, crossing idx 3
        self.assertEqual(x["alerts_per_day"], 2.0)                           # onsets at idx 1 and 3

    def test_block_bootstrap_is_seeded_and_brackets_the_estimate(self):
        rng = np.random.default_rng(1)
        test = pd.DataFrame({"local_date": np.repeat([f"d{i}" for i in range(10)], 20)})
        y = rng.normal(0, 1, 200)
        preds = {"a": y + rng.normal(0, 0.5, 200), "b": y + rng.normal(0, 1.0, 200)}
        code, n = ev.day_index(test)
        s1 = ev.error_stats(y, preds, "b", code, n, ev.resample_matrix(n, FCFG), FCFG)
        s2 = ev.error_stats(y, preds, "b", code, n, ev.resample_matrix(n, FCFG), FCFG)
        self.assertEqual(s1, s2)
        lo, hi = s1["a"]["mae_ci"]
        self.assertLessEqual(lo, s1["a"]["mae"])
        self.assertGreaterEqual(hi, s1["a"]["mae"])
        self.assertLess(s1["a"]["vs_best_baseline"]["mae_diff"], 0)


class Acceptance(unittest.TestCase):
    H = {"60": {"status": "completed", "best_candidate": "random_forest", "best_baseline": "ridge",
                "test": {"random_forest": {"mae": 0.40, "rmse": 0.5,
                                           "vs_best_baseline": {"mae_diff_ci": [-0.05, -0.01], "rmse_diff_ci": None}},
                         "ridge": {"mae": 0.50, "rmse": 0.6, "vs_best_baseline": {}}},
                "alerts": {"models": {"random_forest": {"recall": 0.7, "alerts_per_day": 2.0}}}}}
    RULE = {"set_by": "SYN-team", "set_on": "2026-10-01", "horizon_minutes": 60, "metric": "mae",
            "compare_to": "best_baseline", "min_improvement_pct": 10, "require_ci_excludes_zero": True,
            "min_alert_recall": 0.5, "max_alerts_per_day": 3}

    def test_no_rule_means_not_allowed(self):
        self.assertFalse(apply_acceptance(None, self.H, False)["allowed"])

    def test_synthetic_never_allowed_even_if_rule_passes(self):
        self.assertTrue(apply_acceptance(self.RULE, self.H, False)["allowed"])
        a = apply_acceptance(self.RULE, self.H, True)
        self.assertFalse(a["allowed"])
        self.assertIn("synthetic", a["reason"])

    def test_failing_check_and_template_placeholders(self):
        self.assertFalse(apply_acceptance({**self.RULE, "min_improvement_pct": 25}, self.H, False)["allowed"])
        self.assertFalse(apply_acceptance(FCFG["acceptance_rule_template"], self.H, False)["allowed"])
        empty = {**self.RULE, "min_improvement_pct": None, "require_ci_excludes_zero": None,
                 "min_alert_recall": None, "max_alerts_per_day": None}
        self.assertIn("no criteria", apply_acceptance(empty, self.H, False)["reason"])

    def test_shipped_config_has_no_rule(self):
        self.assertIsNone(FCFG["acceptance_rule"])


class EndToEnd(unittest.TestCase):
    def test_stop_when_not_enough_data(self):
        with tempfile.TemporaryDirectory() as d:
            target, _ = export(read_jsonl(FIX / "SYNTHETIC_sensor_readings.jsonl"), d)
            rep, out, code = run_experiment(target, FCFG, ACFG, Path(d) / "reports")
            self.assertEqual(code, 2)
            self.assertEqual(rep["status"], "stopped_insufficient_data_pipeline_test")
            self.assertEqual(rep["validity"], INVALID)
            self.assertTrue(any("independent local days" in n for n in rep["stop"]["needed"]))
            self.assertNotIn("horizons", rep)                                 # nothing trained
            self.assertTrue((out / "report.md").is_file())

    def test_small_synthetic_run_is_labelled_invalid(self):
        cfg = small_cfg()
        with tempfile.TemporaryDirectory() as d:
            target, _ = export(generate(days=33, pens=("SYN-pen1",)), d)
            df, man = load_export(target)
            self.assertTrue(is_synthetic(df, man))
            cfg["acceptance_rule"] = {**Acceptance.RULE, "horizon_minutes": 30, "min_improvement_pct": -1000,
                                      "require_ci_excludes_zero": None, "min_alert_recall": None,
                                      "max_alerts_per_day": None}
            rep, out, code = run_experiment(target, cfg, ACFG, Path(d) / "reports")
            self.assertEqual(code, 0)
            self.assertEqual(rep["validity"], INVALID)
            self.assertTrue(rep["dataset_version"].startswith("SYNTHETIC-"))
            self.assertTrue(all(c.startswith(f"[{INVALID}]") for c in rep["conclusions"]))
            self.assertFalse(rep["acceptance"]["allowed"])
            h = rep["horizons"]["30"]
            self.assertEqual(h["status"], "completed")
            self.assertEqual(set(h["test"]), {"persistence", "same_time_yesterday", "ridge",
                                             "decision_tree", "random_forest", "gradient_boosting"})
            self.assertIn("models", h["alerts"])
            self.assertFalse(h["held_out_pen"]["possible"])
            md = (out / "report.md").read_text(encoding="utf-8")
            for line in md.splitlines():
                if line.startswith("## ") and line != "## Features":
                    self.assertIn(INVALID, line)
            saved = json.loads((out / "report.json").read_text(encoding="utf-8"))
            self.assertEqual(saved["seed"], cfg["seed"])
            self.assertTrue(saved["features"])


if __name__ == "__main__":
    unittest.main()
