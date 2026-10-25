"""Tests for B1 (THI band), A1 (growth trend + benchmark + pen comparison) and A2 (pen thermal).

ALL DATA AND ALL THRESHOLD VALUES IN THIS FILE ARE SYNTHETIC test values, chosen so the
expected results can be computed by hand. They are not recommendations for the farm.
Run:  python -m unittest discover -s tests -t .
"""
import ast
import copy
import json
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from assess import config as acfg
from assess.benchmark import benchmark_weight, load_benchmark
from assess.growth import add_pen_comparison, assess_growth
from assess.pen_thermal import assess_pen_thermal
from assess.thi_band import assess_thi, band_index, compute_thi

FIX = Path(__file__).resolve().parent / "fixtures"
BENCH = FIX / "SYNTHETIC_pic_benchmark.csv"
NOW = datetime(2026, 10, 19, 12, 0, tzinfo=timezone.utc)
NO_FILE = FIX / "does_not_exist.csv"

SHIPPED = acfg.load()                      # the real config (thresholds still null)


def synthetic_cfg(**sections):
    """Shipped config with SYNTHETIC test values filled in."""
    a = copy.deepcopy(SHIPPED["assessment"])
    a["_synthetic_test_config"] = True
    a["thi"]["categories"]["Grower"] = {"thresholds": [74.0, 79.0], "hysteresis": 1.0}
    a["growth"].update(min_weighins=3, min_interval_days=7, rolling_window_intervals=2,
                       weight_loss_min_kg=0.5, stall_adg_max_g_per_day=200,
                       stall_consecutive_intervals=2, relative_drop_pct=30,
                       relative_drop_min_prior_intervals=2)
    for path, value in sections.items():
        sec, key = path.split("__")
        a[sec][key] = value
    return acfg.build(a, SHIPPED["labels"])


CFG = synthetic_cfg()


def unset_cfg():
    """Real config with every team-supplied value cleared, to test the not_configured paths
    whatever the team has filled in. SYNTHETIC test config."""
    a = copy.deepcopy(SHIPPED["assessment"])
    for c in a["thi"]["categories"].values():
        c["thresholds"], c["hysteresis"] = None, None
    for k in ("min_weighins", "min_interval_days", "rolling_window_intervals", "weight_loss_min_kg",
              "stall_adg_max_g_per_day", "stall_consecutive_intervals", "relative_drop_pct",
              "relative_drop_min_prior_intervals"):
        a["growth"][k] = None
    return acfg.build(a, SHIPPED["labels"])


UNSET = unset_cfg()
SCHEMA_KEYS = {"component", "status", "status_label", "method", "reasons", "inputs",
               "data_quality_warnings", "config_warnings", "config_version", "timestamp",
               "reference_type", "details", "advisory", "disclaimer"}


def all_text(resp):
    return json.dumps(resp, default=str).lower()


# ============================================================================ B1
class THIFormula(unittest.TestCase):
    def test_hand_computed_values(self):
        # (1.8T+32) - (0.55-0.0055RH)(1.8T-26)
        self.assertAlmostEqual(compute_thi(30, 80, CFG), 82.92, places=6)     # 86 - 0.11*28
        self.assertAlmostEqual(compute_thi(25, 50, CFG), 71.775, places=6)    # 77 - 0.275*19
        self.assertAlmostEqual(compute_thi(20, 100, CFG), 68.0, places=6)     # 68 - 0*10
        self.assertAlmostEqual(compute_thi(35, 60, CFG), 86.86, places=6)     # 95 - 0.22*37

    def test_formula_comes_from_config(self):
        a = copy.deepcopy(CFG["assessment"])
        a["thi"]["formula"]["expression"] = "T + RH"
        self.assertEqual(compute_thi(30, 50, acfg.build(a, CFG["labels"])), 80.0)

    def test_unsafe_formula_rejected(self):
        for bad in ["__import__('os').system('x')", "T.real", "X + 1", "'a' * 3"]:
            with self.assertRaises(ValueError):
                acfg.compile_formula(bad, {"T": "", "RH": ""})

    def test_placeholder_formula_is_reported(self):
        a = copy.deepcopy(CFG["assessment"])
        a["thi"]["formula"]["status"] = "placeholder_pending_confirmation"
        r = assess_thi(30, 80, cfg=acfg.build(a, CFG["labels"]), now=NOW)
        self.assertTrue(any("placeholder pending confirmation" in w for w in r["config_warnings"]))


class THIBands(unittest.TestCase):
    T = [74.0, 79.0]

    def test_band_edges(self):
        self.assertEqual(band_index(73.99, self.T, 1.0)[0], 0)
        self.assertEqual(band_index(74.0, self.T, 1.0)[0], 1)    # threshold belongs to upper band
        self.assertEqual(band_index(78.99, self.T, 1.0)[0], 1)
        self.assertEqual(band_index(79.0, self.T, 1.0)[0], 2)

    def test_hysteresis_holds_then_drops(self):
        self.assertEqual(band_index(78.5, self.T, 1.0, previous=2), (2, True))   # >= 79-1
        self.assertEqual(band_index(78.0, self.T, 1.0, previous=2), (2, True))   # edge: 78 >= 78
        self.assertEqual(band_index(77.9, self.T, 1.0, previous=2), (1, False))
        self.assertEqual(band_index(73.2, self.T, 1.0, previous=1), (1, True))
        self.assertEqual(band_index(72.9, self.T, 1.0, previous=1), (0, False))
        self.assertEqual(band_index(73.5, self.T, 1.0, previous=2), (1, True))   # two-level fall, held at 1

    def test_rise_is_immediate(self):
        self.assertEqual(band_index(74.0, self.T, 1.0, previous=0), (1, False))
        self.assertEqual(band_index(79.0, self.T, 1.0, previous=0), (2, False))

    def test_assess_band_and_labels(self):
        r = assess_thi(30, 80, cfg=CFG, now=NOW)                 # THI 82.92
        self.assertEqual((r["status"], r["status_label"]), ("heat_risk", "Heat risk"))
        self.assertEqual(r["details"]["thi"], 82.92)
        self.assertEqual(assess_thi(25, 50, cfg=CFG)["status"], "comfort")   # 71.775
        self.assertEqual(assess_thi(20, 100, cfg=CFG)["status_label"], "Comfort")

    def test_assess_hysteresis_with_previous_band(self):
        t = (78.5 - 32) / 1.8                                    # RH 100 -> THI = 1.8T+32 = 78.5
        held = assess_thi(t, 100, previous_band="heat_risk", cfg=CFG)
        self.assertEqual(held["status"], "heat_risk")
        self.assertTrue(held["details"]["held_by_hysteresis"])
        self.assertEqual(assess_thi(t, 100, cfg=CFG)["status"], "watch")

    def test_thresholds_come_from_config(self):
        cfg = synthetic_cfg()
        cfg["assessment"]["thi"]["categories"]["Grower"]["thresholds"] = [60.0, 65.0]
        self.assertEqual(assess_thi(25, 50, cfg=cfg)["status"], "heat_risk")

    def test_unset_thresholds_not_configured_but_computes_thi(self):
        r = assess_thi(30, 80, cfg=UNSET, now=NOW)
        self.assertEqual(r["status"], "not_configured")
        self.assertEqual(r["details"]["thi"], 82.92)

    def test_bad_inputs(self):
        self.assertEqual(assess_thi(None, 80, cfg=CFG)["status"], "insufficient_data")
        r = assess_thi(30, 130, cfg=CFG)
        self.assertEqual(r["status"], "unavailable")
        self.assertIn("impossible:dht_humidity_pct", r["data_quality_warnings"])
        r = assess_thi(30, 80, quality_flags=["stale_timestamp:ntp_unsynced"], cfg=CFG)
        self.assertEqual(r["status"], "unavailable")

    def test_invalid_threshold_config_raises(self):
        cfg = synthetic_cfg()
        cfg["assessment"]["thi"]["categories"]["Grower"]["thresholds"] = [79.0, 74.0]
        with self.assertRaises(ValueError):
            assess_thi(30, 80, cfg=cfg)


# ============================================================================ A1
PIG = {"pig_id": "SYN-pig-1", "birth_date": "2026-06-01", "sex": "Female", "breed": "SYN-breed"}


def weighins(*pairs, source="manual"):
    return [{"id": f"SYN-w{i}", "date": d, "weight_kg": kg, "source": source} for i, (d, kg) in enumerate(pairs)]


BASE = [("2026-07-01", 10.0), ("2026-07-08", 13.5), ("2026-07-15", 17.0)]   # 500 g/d, 500 g/d


def grow(extra, cfg=CFG, pig=PIG, bench=NO_FILE):
    return assess_growth(pig, weighins(*BASE, *extra), cfg=cfg, now=NOW, benchmark_path=bench)


def flag_names(r):
    return [f["flag"] for f in r["details"]["flags"]]


class GrowthADG(unittest.TestCase):
    def test_adg_and_rolling_adg_hand_computed(self):
        r = grow([("2026-07-22", 20.5)])
        self.assertEqual(r["status"], "no_flags")
        self.assertEqual([iv["adg_g_per_day"] for iv in r["details"]["intervals"]], [500.0, 500.0, 500.0])
        self.assertEqual(r["details"]["rolling_adg_g_per_day"], 500.0)      # (20.5-13.5)/14 d
        self.assertEqual(r["details"]["latest_adg_g_per_day"], 500.0)
        self.assertEqual(r["method"], "rule")
        self.assertTrue(all(i["source"] == "manual" for i in r["inputs"]))

    def test_rolling_window_uses_time_weighted_span(self):
        r = grow([("2026-07-29", 18.4)])        # last two intervals span 13.5 kg (07-08) -> 18.4 kg (07-29)
        self.assertEqual(r["details"]["rolling_adg_g_per_day"], round((18.4 - 13.5) / 21 * 1000, 1))

    def test_insufficient_data_states_requirement(self):
        r = assess_growth(PIG, weighins(*BASE[:2]), cfg=CFG, benchmark_path=NO_FILE)
        self.assertEqual(r["status"], "insufficient_data")
        self.assertIn("at least 3 weigh-ins at least 7 day(s) apart", r["reasons"][0])

    def test_too_close_weighins_are_skipped_not_averaged(self):
        r = assess_growth(PIG, weighins(("2026-07-01", 10.0), ("2026-07-03", 11.0),
                                        ("2026-07-08", 13.5), ("2026-07-15", 17.0)),
                          cfg=CFG, benchmark_path=NO_FILE)
        self.assertEqual(len(r["details"]["intervals"]), 2)
        self.assertTrue(any("SYN-w1 not used" in w for w in r["data_quality_warnings"]))

    def test_sensor_weights_and_fake_birth_weight_are_ignored(self):
        ws = weighins(*BASE, ("2026-07-22", 20.5))
        ws.append({"id": "SYN-sensor", "date": "2026-07-29", "weight_kg": 50.0, "source": "sensor"})
        ws.append({"id": "SYN-birth", "date": "2026-06-01", "weight_kg": 1.4, "notes": "Birth weight"})
        r = assess_growth(PIG, ws, cfg=CFG, benchmark_path=NO_FILE)
        self.assertEqual(r["status"], "no_flags")
        w = " ".join(r["data_quality_warnings"])
        self.assertIn("SYN-sensor ignored", w)
        self.assertIn("SYN-birth ignored", w)

    def test_unset_growth_rules_are_not_configured(self):
        r = assess_growth(PIG, weighins(*BASE), cfg=UNSET, benchmark_path=NO_FILE)
        self.assertEqual(r["status"], "not_configured")


class GrowthFlags(unittest.TestCase):
    def test_weight_loss(self):
        r = grow([("2026-07-22", 16.0)])                          # -1.0 kg >= 0.5
        self.assertEqual(r["status"], "flags_raised")
        self.assertIn("weight_loss", flag_names(r))

    def test_loss_below_tolerance_is_not_weight_loss(self):
        r = grow([("2026-07-22", 16.8)])                          # -0.2 kg < 0.5
        self.assertNotIn("weight_loss", flag_names(r))

    def test_stalled_gain(self):
        r = assess_growth(PIG, weighins(("2026-07-01", 10.0), ("2026-07-08", 13.5),
                                        ("2026-07-15", 14.5), ("2026-07-22", 15.5)),
                          cfg=CFG, benchmark_path=NO_FILE)        # last two ADG 142.9 <= 200
        self.assertIn("stalled_gain", flag_names(r))

    def test_one_slow_interval_is_not_stalled(self):
        r = grow([("2026-07-22", 18.0)])                          # 142.9 once; need 2
        self.assertNotIn("stalled_gain", flag_names(r))

    def test_relative_drop_only(self):
        r = grow([("2026-07-22", 19.0)])          # 285.7 < 500*(1-0.30)=350; not stalled, no loss
        self.assertEqual(flag_names(r), ["relative_drop"])

    def test_no_relative_drop_above_limit(self):
        r = grow([("2026-07-22", 19.6)])                          # 371.4 > 350
        self.assertEqual(flag_names(r), [])

    def test_relative_drop_needs_prior_intervals(self):
        r = assess_growth(PIG, weighins(*BASE), cfg=CFG, benchmark_path=NO_FILE)   # 1 prior < 2
        self.assertTrue(any("needs 2 earlier interval" in x for x in r["reasons"]))

    def test_unset_rule_is_reported_not_guessed(self):
        cfg = synthetic_cfg(growth__weight_loss_min_kg=None)
        r = grow([("2026-07-22", 16.0)], cfg=cfg)
        self.assertNotIn("weight_loss", flag_names(r))
        self.assertIn("weight-loss rule not configured", r["reasons"])

    def test_never_classifies_normal_under_over(self):
        for extra in ([("2026-07-22", 20.5)], [("2026-07-22", 16.0)], [("2026-07-22", 40.0)]):
            text = all_text(grow(extra, bench=BENCH))
            for word in ("underweight", "overweight", '"normal"'):
                self.assertNotIn(word, text)


class Benchmark(unittest.TestCase):
    BCFG = SHIPPED["assessment"]["growth"]["benchmark"]
    PIG35 = [("2026-06-22", 6.0), ("2026-06-29", 8.0), ("2026-07-06", 10.5)]   # last weigh-in: age 35 d

    def test_loads_context_only_rows_only(self):
        rows, warnings = load_benchmark(self.BCFG, BENCH)
        self.assertEqual(rows, [(21.0, 6.0), (49.0, 15.0), (77.0, 35.0), (196.0, 140.0)])
        self.assertTrue(any("ignored 2 row" in w for w in warnings))

    def test_interpolation_and_range(self):
        rows, _ = load_benchmark(self.BCFG, BENCH)
        self.assertAlmostEqual(benchmark_weight(rows, 35), 10.5)          # 6 + 9*(14/28)
        self.assertEqual(benchmark_weight(rows, 21), 6.0)
        self.assertEqual(benchmark_weight(rows, 196), 140.0)
        self.assertIsNone(benchmark_weight(rows, 20))                      # no extrapolation
        self.assertIsNone(benchmark_weight(rows, 197))

    def test_shown_with_exact_label(self):
        r = assess_growth(PIG, weighins(*self.PIG35), cfg=CFG, benchmark_path=BENCH)
        b = r["details"]["benchmark"]
        self.assertTrue(b["shown"])
        self.assertEqual(b["pct_of_benchmark"], 100.0)
        self.assertEqual(b["label"], "Commercial benchmark for optimized PIC-sired pigs (PIC Wean to "
                                     "Finish Guidelines 2019). Context only; not a standard for this farm.")
        self.assertEqual(r["reference_type"], "context_only")

    def test_missing_file_fallback(self):
        r = assess_growth(PIG, weighins(*self.PIG35), cfg=CFG, benchmark_path=NO_FILE)
        self.assertEqual(r["details"]["benchmark"]["message"], "no reference available")
        self.assertIsNone(r["reference_type"])
        self.assertIn(r["status"], ("no_flags", "flags_raised"))

    def test_out_of_range_fallback(self):
        old = {**PIG, "birth_date": "2026-01-01"}                          # age > 196 d
        r = assess_growth(old, weighins(*BASE, ("2026-07-22", 20.5)), cfg=CFG, benchmark_path=BENCH)
        self.assertFalse(r["details"]["benchmark"]["shown"])
        self.assertEqual(r["details"]["benchmark"]["message"], "no reference available")
        self.assertEqual(r["status"], "no_flags")

    def test_benchmark_cannot_raise_flag_or_change_status(self):
        with tempfile.TemporaryDirectory() as d:
            extreme = Path(d) / "SYNTHETIC_extreme_benchmark.csv"         # 100x heavier than the pig
            col = SHIPPED["assessment"]["growth"]["benchmark"]["columns"]["weight_kg"]   # file's column name
            extreme.write_text(f"age_days,{col},use\n21,600,context_only\n196,14000,context_only\n")
            cases = [[("2026-07-22", 20.5)], [("2026-07-22", 16.0)], [("2026-07-22", 19.0)]]
            for extra in cases:
                runs = [grow(extra, bench=b) for b in (NO_FILE, BENCH, extreme)]
                for r in runs[1:]:
                    self.assertEqual(r["status"], runs[0]["status"])
                    self.assertEqual(r["details"]["flags"], runs[0]["details"]["flags"])
                    self.assertEqual(r["reasons"], runs[0]["reasons"])
                self.assertTrue(runs[2]["details"]["benchmark"]["shown"])  # extreme one was used


class PenComparison(unittest.TestCase):
    def test_relative_to_pen_median_without_changing_status(self):
        pigs = [("SYN-a", 20.5), ("SYN-b", 19.1), ("SYN-c", 21.9)]       # rolling 500 / 400 / 600
        rs = [grow([("2026-07-22", w)], pig={**PIG, "pig_id": pid, "pen_id": "SYN-pen1"}) for pid, w in pigs]
        rs.append(grow([("2026-07-22", 20.5)], pig={**PIG, "pig_id": "SYN-nopen"}))
        out = add_pen_comparison(rs, CFG)
        cmp = {r["details"]["pig_id"]: r["details"].get("pen_comparison") for r in out}
        self.assertEqual(cmp["SYN-a"]["pen_median_adg_g_per_day"], 500.0)
        self.assertEqual((cmp["SYN-b"]["difference_g_per_day"], cmp["SYN-b"]["pct_of_pen_median"]), (-100.0, 80.0))
        self.assertEqual(cmp["SYN-c"]["pct_of_pen_median"], 120.0)
        self.assertIn("not a verdict", cmp["SYN-a"]["note"])
        self.assertIsNone(cmp["SYN-nopen"])
        self.assertEqual([r["status"] for r in out], [r["status"] for r in rs])

    def test_single_pig_pen_has_no_comparison(self):
        r = grow([("2026-07-22", 20.5)], pig={**PIG, "pen_id": "SYN-pen9"})
        self.assertNotIn("pen_comparison", add_pen_comparison([r], CFG)[0]["details"])


# ============================================================================ A2
T_CUR = datetime(2026, 10, 19, 14, 0, tzinfo=timezone.utc)


def reading(t, amg, amb, pen="SYN-pen1", **kw):
    return {"timestamp_utc": t, "amg_summary_c": amg, "dht_temp_c": amb, "pen_id": pen,
            "_synthetic": True, **kw}


def history(n=40, spread=0.1, amb=29.0, start=T_CUR - timedelta(days=2), **kw):
    """SYNTHETIC baseline: values 32 + {-2,-1,0,1,2}*spread, every 30 min."""
    return [reading(start + timedelta(minutes=30 * i), 32.0 + ((i % 5) - 2) * spread, amb, **kw)
            for i in range(n)]


class PenThermal(unittest.TestCase):
    def test_unusual_with_mad_floor(self):
        # median 32.0, MAD 0.1 -> 1.4826*0.1 = 0.148 < floor 0.25 -> sd 0.25; z = 1.0/0.25 = 4.0
        r = assess_pen_thermal(reading(T_CUR, 33.0, 29.2), history(), cfg=CFG, now=NOW)
        self.assertEqual(r["status"], "unusual")
        self.assertEqual(r["method"], "statistical")
        self.assertEqual(r["details"]["robust_z"], 4.0)
        self.assertEqual(r["details"]["robust_sd_c"], 0.25)
        self.assertEqual(r["reasons"][0], "unusual thermal reading in this pen; check the pigs")

    def test_typical_with_real_mad(self):
        h = history(spread=0.5)                    # MAD 0.5 -> sd 0.7413
        r = assess_pen_thermal(reading(T_CUR, 34.0, 29.0), h, cfg=CFG)
        self.assertEqual(r["status"], "typical")
        self.assertAlmostEqual(r["details"]["robust_z"], round(2.0 / (1.4826 * 0.5), 2))
        self.assertEqual(assess_pen_thermal(reading(T_CUR, 35.0, 29.0), h, cfg=CFG)["status"], "unusual")

    def test_low_reading_and_direction_config(self):
        self.assertEqual(assess_pen_thermal(reading(T_CUR, 31.0, 29.0), history(), cfg=CFG)["status"], "unusual")
        cfg = synthetic_cfg(pen_thermal__flag_direction="high")
        self.assertEqual(assess_pen_thermal(reading(T_CUR, 31.0, 29.0), history(), cfg=cfg)["status"], "typical")

    def test_baseline_is_conditioned_on_ambient_bin(self):
        r = assess_pen_thermal(reading(T_CUR, 33.0, 35.0), history(), cfg=CFG)   # bin 34-36: empty
        self.assertEqual(r["status"], "insufficient_baseline")
        self.assertIn("has 0 reading(s) for ambient 34 to 36 degC", r["reasons"][0])
        self.assertIn("needs 30 (30 more)", r["reasons"][0])

    def test_insufficient_baseline_says_how_much(self):
        r = assess_pen_thermal(reading(T_CUR, 33.0, 29.0), history(n=10), cfg=CFG)
        self.assertEqual(r["status"], "insufficient_baseline")
        self.assertEqual(r["details"]["baseline_n"], 10)
        self.assertIn("needs 30 (20 more)", r["reasons"][0])

    def test_window_future_other_pen_and_bad_quality_excluded(self):
        old = history(start=T_CUR - timedelta(days=20))                         # outside 14 d
        future = history(start=T_CUR + timedelta(minutes=1))                    # after the reading
        other = history(pen="SYN-pen2")
        bad = history(quality="bad")
        for h in (old, future, other):
            self.assertEqual(assess_pen_thermal(reading(T_CUR, 33.0, 29.0), h, cfg=CFG)["details"]["baseline_n"], 0)
        r = assess_pen_thermal(reading(T_CUR, 33.0, 29.0), bad, cfg=CFG)
        self.assertEqual(r["details"]["baseline_n"], 0)
        self.assertTrue(any("40 earlier reading(s) excluded" in w for w in r["data_quality_warnings"]))

    def test_time_of_day_blocks(self):
        cfg = synthetic_cfg(pen_thermal__time_of_day_block_hours=6)
        night = history(start=T_CUR.replace(hour=0) - timedelta(days=1), n=12)   # 00:00-05:30
        r = assess_pen_thermal(reading(T_CUR, 33.0, 29.0), night * 3, cfg=cfg)    # current 14:00 block 2
        self.assertEqual(r["status"], "insufficient_baseline")

    def test_current_reading_unusable(self):
        r = assess_pen_thermal(reading(T_CUR, 33.0, 29.0, amg_summary_c__state="sensor_offline"),
                               history(), cfg=CFG)
        self.assertEqual(r["status"], "unavailable")
        r = assess_pen_thermal(reading(T_CUR, None, 29.0), history(), cfg=CFG)
        self.assertEqual(r["status"], "unavailable")

    def test_wording_never_diagnostic_or_per_pig(self):
        outs = [assess_pen_thermal(reading(T_CUR, v, 29.0), history(), cfg=CFG) for v in (33.0, 32.0, 31.0)]
        outs.append(assess_pen_thermal(reading(T_CUR, 33.0, 29.0), history(n=3), cfg=CFG))
        for r in outs:
            text = all_text(r)
            for word in ("fever", "disease", "diagnos", "sick", "illness", "infection", "pig_id"):
                self.assertNotIn(word, text.replace("not a veterinary diagnosis", ""))
            self.assertTrue(all(i["source"] == "sensor" for i in r["inputs"]))

    def test_pending_defaults_reported(self):
        r = assess_pen_thermal(reading(T_CUR, 33.0, 29.0), history(), cfg=CFG)
        self.assertTrue(any("pending review" in w for w in r["config_warnings"]))


# ============================================================================ common
class CommonSchema(unittest.TestCase):
    def test_all_components_return_the_common_schema(self):
        outs = [assess_thi(30, 80, cfg=CFG, now=NOW), assess_thi(None, None, cfg=CFG),
                assess_thi(30, 80, cfg=SHIPPED),
                grow([("2026-07-22", 20.5)], bench=BENCH),
                assess_growth(PIG, [], cfg=CFG, benchmark_path=NO_FILE),
                assess_pen_thermal(reading(T_CUR, 33.0, 29.0), history(), cfg=CFG),
                assess_pen_thermal(reading(T_CUR, 33.0, 29.0), [], cfg=CFG)]
        for r in outs:
            self.assertEqual(set(r), SCHEMA_KEYS, r["component"])
            self.assertIn(r["method"], ("rule", "statistical"))
            self.assertEqual(r["config_version"], r["config_version"].strip())
            self.assertTrue(all(i["source"] in ("sensor", "manual") for i in r["inputs"]))
            self.assertTrue(r["advisory"])
            json.dumps(r)                                       # JSON-serialisable
        self.assertEqual(outs[0]["timestamp"], NOW.isoformat())

    def test_config_version_changes_with_config(self):
        self.assertNotEqual(CFG["version"], SHIPPED["version"])
        a, lab = SHIPPED["assessment"]["version"], SHIPPED["labels"]["version"]
        self.assertTrue(SHIPPED["version"].startswith(f"assessment-{a}/labels-{lab}+"))

    def test_no_threshold_literals_in_component_code(self):
        """Only unit conversions, indexes and rounding digits may appear as numbers in code."""
        allowed = {0, 1, 2, 3, 100, 1000, 86400}
        root = Path(__file__).resolve().parent.parent / "assess"
        for name in ("thi_band.py", "growth.py", "pen_thermal.py", "benchmark.py"):
            tree = ast.parse((root / name).read_text(encoding="utf-8"))
            nums = {n.value for n in ast.walk(tree)
                    if isinstance(n, ast.Constant) and isinstance(n.value, (int, float))
                    and not isinstance(n.value, bool)}
            self.assertTrue(nums <= allowed, f"{name}: numeric literals {sorted(nums - allowed)}")


if __name__ == "__main__":
    unittest.main()
