"""Retraining workflow tests. ALL DATA, MODELS AND TOKENS HERE ARE SYNTHETIC.

Synthetic data can never pass the evaluation gate (by design). To test the eligible ->
approve -> activate -> rollback path, ONE test patches the baseline half of the gate
(report_gate) and says so; the production comparison and everything after it run for real.
"""
import copy
import json
import tempfile
import threading
import time
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

import joblib
import numpy as np
from sklearn.dummy import DummyRegressor

import forecast.retrain as rt
from app.main import create_app, init_state
from app.registry import JobLock, LockBusy, ModelState, Registry, RegistryError
from app.settings import api_config
from assess import config as acfg_mod
from forecast.run import load_config, pipeline_test_configs
from pipeline.export import export, read_jsonl
from tests.asgi_client import request
from tests.fixtures.synthetic_forecast import generate
from tests.test_api import ADMIN, USER, FakeVerifier, auth, readings
from tests.test_forecast import small_cfg

FIX = Path(__file__).resolve().parent / "fixtures"
RULE = {"set_by": "SYN-team", "set_on": "2026-10-01", "horizon_minutes": 30, "metric": "mae",
        "compare_to": "best_baseline", "min_improvement_pct": 5, "require_ci_excludes_zero": None,
        "min_alert_recall": None, "max_alerts_per_day": None}


def cfg(**rule):
    c = small_cfg()
    c["acceptance_rule"] = {**RULE, **rule}
    return c


class RetrainBase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        root = Path(cls.tmp.name)
        cls.exports = root / "exports"
        cls.dataset, _ = export(generate(days=33, pens=("SYN-pen1",)), cls.exports)       # SYNTHETIC
        cls.small, _ = export(read_jsonl(FIX / "SYNTHETIC_sensor_readings.jsonl"), cls.exports)
        cls.acfg = pipeline_test_configs(acfg_mod.load(), load_config())

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def setUp(self):
        self.reg_tmp = tempfile.TemporaryDirectory()
        self.reg = Registry(Path(self.reg_tmp.name) / "registry",
                            {**api_config()["registry"], "allow_synthetic_models": True})   # test registry
        self.state = ModelState(self.reg)

    def tearDown(self):
        self.reg_tmp.cleanup()

    def run_job(self, fcfg=None, dataset=None, **kw):
        return rt.run_job(self.reg, dataset or self.dataset, by="SYN-admin", trigger="test",
                          fcfg=fcfg or cfg(), acfg=self.acfg, **kw)

    def production(self, version, features, offset):
        """SYNTHETIC approved 'production' model that predicts a constant change."""
        d = self.reg.root / version
        d.mkdir(parents=True)
        m = DummyRegressor(strategy="constant", constant=offset).fit(np.zeros((2, len(features))), [offset] * 2)
        joblib.dump(m, d / "model.joblib")
        (d / "metadata.json").write_text(json.dumps({
            "version": version, "status": "approved", "target": "thi", "horizon_minutes": 30, "predict": "delta",
            "features": features, "training_config": cfg(), "dataset_synthetic": True,
            "thi_formula": self.acfg["assessment"]["thi"]["formula"]["expression"]}))
        self.state.activate(version, by="SYN-admin")


class JobRecordsAndRejection(RetrainBase):
    def test_synthetic_candidate_is_rejected_and_cannot_be_served(self):
        rec = self.run_job()
        self.assertEqual(rec["status"], "rejected")
        self.assertIn("synthetic", rec["rejection_reason"])
        for k in ("job_id", "requested_at", "finished_at", "dataset_version", "record_count", "independent_days",
                  "feature_schema", "config", "seed", "metrics", "previous_version", "candidate_version", "gate"):
            self.assertIn(k, rec)
        self.assertTrue(rec["dataset_version"].startswith("SYNTHETIC-"))
        self.assertGreater(rec["independent_days"], 30)
        self.assertTrue(rec["feature_schema"])
        meta = self.reg.metadata(rec["candidate_version"])
        self.assertEqual(meta["status"], "rejected")
        self.assertEqual([h["to"] for h in meta["history"]], ["rejected"])
        with self.assertRaises(RegistryError):
            self.state.activate(rec["candidate_version"], by="SYN-admin")         # not servable
        with self.assertRaises(RegistryError):
            self.state.approve(rec["candidate_version"], by="SYN-admin")          # rejected -> approved refused
        self.assertIsNone(self.reg.read_pointer()["active"])
        saved = self.reg.job(rec["job_id"])
        self.assertEqual(saved["status"], "rejected")
        self.assertTrue(Path(saved["report"]).is_file())

    def test_no_acceptance_rule_means_no_candidate(self):
        c = small_cfg()                       # acceptance_rule is null, as shipped
        rec = self.run_job(fcfg=c)
        self.assertEqual(rec["status"], "rejected")
        self.assertIn("acceptance_rule", rec["rejection_reason"])
        self.assertIsNone(rec["candidate_version"])
        self.assertEqual(self.reg.versions(), [])

    def test_insufficient_data_is_rejected_before_training(self):
        rec = self.run_job(dataset=self.small)
        self.assertEqual(rec["status"], "rejected")
        self.assertIn("experiment stopped", rec["rejection_reason"])
        self.assertEqual(self.reg.versions(), [])

    def test_training_failure_is_recorded_and_lock_released(self):
        with mock.patch.object(rt, "run_experiment", side_effect=RuntimeError("SYN boom")):
            rec = self.run_job()
        self.assertEqual(rec["status"], "failed")
        self.assertIn("SYN boom", rec["error"])
        self.assertFalse((self.reg.root / ".job.lock").exists())
        self.assertEqual(self.reg.versions(), [])
        retry = self.run_job()                       # a failed job may be retried
        self.assertEqual(retry["status"], "rejected")
        self.assertEqual(retry["previous_attempts"][0]["status"], "failed")

    def test_repeat_request_is_not_a_second_model(self):
        first = self.run_job()
        again = self.run_job()
        self.assertTrue(again.get("duplicate_request"))
        self.assertEqual(again["candidate_version"], first["candidate_version"])
        self.assertEqual(len(self.reg.versions()), 1)


class GateAgainstProduction(RetrainBase):
    def features(self):
        rec = self.run_job(fcfg=cfg(min_improvement_pct=4))    # rejected (synthetic); gives the feature list
        return rec["feature_schema"]

    def test_eligible_approve_activate_rollback(self):
        feats = self.features()
        self.production("SYN-prod-bad", feats, offset=50.0)    # production predicts THI +50: terrible
        with mock.patch.object(rt, "report_gate", return_value=(True, "SIMULATED baseline pass (test only)")):
            rec = self.run_job(fcfg=cfg(min_improvement_pct=5))
        self.assertEqual(rec["status"], "eligible", rec.get("rejection_reason") or rec.get("error"))
        self.assertEqual(rec["previous_version"], "SYN-prod-bad")
        self.assertTrue(rec["gate"]["vs_production"]["passed"])
        v = rec["candidate_version"]
        self.assertEqual(self.reg.read_pointer()["active"], "SYN-prod-bad")      # gate never deploys
        with self.assertRaises(RegistryError):
            self.state.activate(v, by="SYN-admin")                               # eligible is not approved
        self.state.approve(v, by="SYN-admin", note="SYN review")
        self.assertEqual(self.reg.metadata(v)["status"], "approved")
        with self.assertRaises(RegistryError):
            self.state.approve(v, by="SYN-admin")                                # only from eligible
        p = self.state.activate(v, by="SYN-admin")
        self.assertEqual((p["active"], p["previous"]), (v, "SYN-prod-bad"))
        self.assertEqual(self.state.snapshot()[2], v)
        p = self.state.rollback(by="SYN-admin")
        self.assertEqual((p["active"], p["previous"]), ("SYN-prod-bad", v))

    def test_candidate_that_does_not_beat_production_is_rejected(self):
        feats = self.features()
        self.production("SYN-prod", feats, offset=0.0)
        with mock.patch.object(rt, "report_gate", return_value=(True, "SIMULATED baseline pass (test only)")):
            rec = self.run_job(fcfg=cfg(min_improvement_pct=1000))              # impossible bar
        self.assertEqual(rec["status"], "rejected")
        self.assertIn("production", rec["rejection_reason"])
        self.assertEqual(self.reg.metadata(rec["candidate_version"])["status"], "rejected")
        self.assertEqual(self.reg.read_pointer()["active"], "SYN-prod")

    def test_incomparable_production_is_rejected(self):
        self.production("SYN-prod-other", ["only_one_feature"], offset=0.0)
        with mock.patch.object(rt, "report_gate", return_value=(True, "SIMULATED baseline pass (test only)")):
            rec = self.run_job()
        self.assertEqual(rec["status"], "rejected")
        self.assertIn("not comparable", rec["rejection_reason"])


class Concurrency(RetrainBase):
    def test_lock_blocks_training_and_activation(self):
        with self.reg.lock("SYN-other-job"):
            with self.assertRaises(LockBusy):
                self.run_job()
            with self.assertRaises(LockBusy):
                self.state.rollback(by="SYN-admin")
        self.assertFalse((self.reg.root / ".job.lock").exists())

    def test_two_simultaneous_jobs_only_one_runs(self):
        started = threading.Event()

        def slow(*a, **k):
            started.set()
            time.sleep(1.0)
            raise RuntimeError("SYN stop after holding the lock")

        results = []
        with mock.patch.object(rt, "run_experiment", side_effect=slow):
            t = threading.Thread(target=lambda: results.append(self.run_job()))
            t.start()
            started.wait(5)
            with self.assertRaises(LockBusy):
                self.run_job()
            t.join()
        self.assertEqual(results[0]["status"], "failed")

    def test_stale_lock_is_broken(self):
        lock_path = self.reg.root / ".job.lock"
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        lock_path.write_text(json.dumps({"owner": "SYN-crashed", "since": time.time() - 10 ** 6}))
        with JobLock(lock_path, "SYN-new", stale_after_s=60):
            self.assertIn("SYN-new", lock_path.read_text())


class FirebaseFailures(unittest.TestCase):
    def test_firestore_read_failure_writes_no_dataset(self):
        from pipeline import export as exp, firestore_io
        with tempfile.TemporaryDirectory() as d, \
                mock.patch.object(firestore_io, "fetch_readings", side_effect=ConnectionError("SYN unavailable")):
            with self.assertRaises(ConnectionError):
                exp.main(["--firestore", "--start", "2026-10-01", "--out", d])
            self.assertEqual(list(Path(d).iterdir()), [])

    def test_firestore_write_failure_on_correction_is_raised(self):
        from pipeline import corrections, firestore_io
        with mock.patch.object(firestore_io, "fetch_corrections", return_value=[]), \
                mock.patch.object(firestore_io, "write_correction", side_effect=PermissionError("SYN denied")):
            with self.assertRaises(PermissionError):
                corrections.main(["--record-id", "SYN-r1", "--set", "dht_temp_c=30.1",
                                  "--reason", "SYN", "--author", "SYN"])


class RetrainAPI(RetrainBase):
    def start(self):
        app = create_app()
        init_state(app, verifier=FakeVerifier(), registry_root=self.reg.root, registry_cfg=self.reg.cfg,
                   clock=lambda: datetime(2026, 10, 19, 6, 0, tzinfo=timezone.utc),
                   exports_dir=self.exports, run_in_background=lambda fn: fn())     # synchronous in tests
        app.state.acfg = self.acfg
        self.app = app
        return app

    def call(self, method, path, json=None, token=None):
        return request(self.app, method, path, json=json, headers=auth(token) if token else None)

    def test_retrain_endpoint_auth_and_flow(self):
        self.start()
        body = {"dataset_version": self.small.name}
        self.assertEqual(self.call("POST", "/admin/retrain", body).status_code, 401)
        self.assertEqual(self.call("POST", "/admin/retrain", body, USER).status_code, 403)
        self.assertEqual(self.call("GET", "/admin/jobs", token=USER).status_code, 403)
        self.assertEqual(self.call("POST", "/admin/retrain", {"dataset_version": "../x"}, ADMIN).status_code, 422)
        self.assertEqual(self.call("POST", "/admin/retrain", {"dataset_version": "SYN-missing"}, ADMIN).status_code, 404)
        r = self.call("POST", "/admin/retrain", body, ADMIN)
        self.assertEqual(r.status_code, 202, r.content)
        jid = r.json()["job_id"]
        job = self.call("GET", f"/admin/jobs/{jid}", token=ADMIN).json()
        self.assertEqual(job["status"], "rejected")                    # insufficient synthetic data
        again = self.call("POST", "/admin/retrain", body, ADMIN)
        self.assertEqual((again.status_code, again.json()["duplicate_request"]), (200, True))
        self.assertEqual(len(self.call("GET", "/admin/jobs", token=ADMIN).json()["jobs"]), 1)

    def test_retrain_conflict_and_inference_keeps_working(self):
        self.start()
        with self.reg.lock("SYN-running-job"):
            r = self.call("POST", "/admin/retrain", {"dataset_version": self.small.name}, ADMIN)
            self.assertEqual(r.status_code, 409)
            self.assertEqual(self.call("POST", "/models/rollback", token=ADMIN).status_code, 409)
            env = self.call("POST", "/assess/environment", {"readings": readings()}, USER)
            self.assertEqual(env.status_code, 200)                     # inference is not blocked by jobs

    def test_approve_endpoint(self):
        d = self.reg.root / "SYN-elig"
        d.mkdir(parents=True)
        (d / "metadata.json").write_text(json.dumps({"version": "SYN-elig", "status": "eligible"}))
        self.start()
        self.assertEqual(self.call("POST", "/models/SYN-elig/approve", {}, USER).status_code, 403)
        r = self.call("POST", "/models/SYN-elig/approve", {"note": "SYN reviewed"}, ADMIN)
        self.assertEqual((r.status_code, r.json()["status"]), (200, "approved"))
        self.assertEqual(r.json()["history"][-1]["by"], "SYN-a1")
        self.assertEqual(self.call("POST", "/models/SYN-elig/approve", {}, ADMIN).status_code, 409)


if __name__ == "__main__":
    unittest.main()
