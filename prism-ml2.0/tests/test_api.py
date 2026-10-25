"""API tests. ALL tokens, models, readings and thresholds here are SYNTHETIC test values.

Run:  python -m unittest discover -s tests -t .
"""
import copy
import json
import logging
import re
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

import joblib
import numpy as np
import pandas as pd
from sklearn.dummy import DummyRegressor

import app.registry as registry_mod
from app.main import create_app, init_state
from app.settings import api_config
from forecast.features import build_frame
from forecast.run import load_config
from tests.asgi_client import request
from tests.test_assessment import synthetic_cfg

NOW = datetime(2026, 10, 19, 6, 0, tzinfo=timezone.utc)
USER, ADMIN = "SYN-user-token", "SYN-admin-token"
FCFG = load_config()
ACFG = synthetic_cfg()                                    # SYNTHETIC THI thresholds [74, 79]


class FakeVerifier:
    def verify(self, token):
        if token == USER:
            return {"uid": "SYN-u1"}
        if token == ADMIN:
            return {"uid": "SYN-a1", "role": "admin"}
        raise ValueError("bad token")


def auth(token):
    return {"Authorization": f"Bearer {token}"}


def synthetic_features():
    t = pd.date_range("2026-08-01T00:00:00Z", periods=2 * 288, freq="5min")
    temp = 28 + np.sin(np.arange(len(t)) / 288 * 2 * np.pi)
    grid = pd.DataFrame({"pen": "SYN", "time": t, "temp": temp, "hum": 80.0, "thi": temp + 50,
                         "n_records": 1, "n_fault": 0, "mist_on": 0.0, "mist_active_s": 0.0})
    return build_frame(grid, FCFG, 30)[1]


FEATURES = synthetic_features()


def make_version(root, version, offset, status="approved", corrupt=False, synthetic=True):
    d = Path(root) / version
    d.mkdir(parents=True)
    if corrupt:
        (d / "model.joblib").write_bytes(b"SYNTHETIC not a pickle")
    else:
        m = DummyRegressor(strategy="constant", constant=offset).fit(np.zeros((2, len(FEATURES))), [offset] * 2)
        joblib.dump(m, d / "model.joblib")
    (d / "metadata.json").write_text(json.dumps({
        "version": version, "status": status, "target": "thi", "horizon_minutes": 30, "predict": "delta",
        "features": FEATURES, "training_config": FCFG, "dataset_version": "SYNTHETIC-test",
        "dataset_synthetic": synthetic, "thi_formula": ACFG["assessment"]["thi"]["formula"]["expression"],
        "metrics": {"mae": 0.1, "_synthetic": True}, "evaluation": {"_synthetic": True}}))


def readings(n=37, end=NOW - timedelta(seconds=10), temp=30.0, hum=80.0, mist=False, **last):
    rs = [{"timestamp": (end - timedelta(minutes=5 * (n - 1 - i))).isoformat(), "dht_temp_c": temp,
           "dht_humidity_pct": hum, "dht_temp_valid": True, "dht_humidity_valid": True,
           "sprinkler_on": mist, "sprinkler_active_s": 0} for i in range(n)]
    rs[-1].update(last)
    return rs


class APITest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / "registry"
        self.root.mkdir()
        self.reg_cfg = {**api_config()["registry"], "allow_synthetic_models": True}   # SYNTHETIC test registry
        self.app = None

    def tearDown(self):
        self.tmp.cleanup()

    def start(self, verifier=FakeVerifier()):
        self.app = create_app()
        init_state(self.app, verifier=verifier, registry_root=self.root, registry_cfg=self.reg_cfg,
                   clock=lambda: NOW)
        self.app.state.acfg = ACFG
        return self.app

    def call(self, method, path, json=None, token=None, **kw):
        return request(self.app or self.start(), method, path, json=json,
                       headers=auth(token) if token else None, **kw)

    def env(self, rs=None, token=USER):
        return self.call("POST", "/assess/environment", {"pen_id": "SYN-pen", "readings": rs or readings()}, token)


class ExistingEndpoints(APITest):
    def test_health_and_old_predict_routes_unchanged(self):
        self.assertEqual(self.call("GET", "/health").json(), {"status": "ok"})
        r = self.call("POST", "/predict/farm", {"body_temp": 34, "ambient_temp": 30, "humidity": 80})
        self.assertEqual(r.status_code, 200)
        self.assertIn("status", r.json())
        r = self.call("POST", "/predict/pig-growth", {"age_days": 98, "current_weight_kg": 54,
                                                      "previous_weight_kg": 47.5, "days_between": 7})
        self.assertEqual(r.json()["status"], "Within Expected")

    def test_flutter_farm_call_works(self):
        payload = {"temperature_c": 30.0, "humidity_pct": 80.0, "weight_change_kg": 0.0,
                   "feed_intake_kg": 0.0, "medicine_given": 0}            # exactly what ml_service.dart sends
        r = self.call("POST", "/api/farm/analyze", payload, USER)
        self.assertEqual(r.status_code, 200, r.content)
        body = r.json()
        self.assertEqual(body["condition"], "Heat risk")                  # THI 82.92 >= 79 (synthetic bands)
        self.assertTrue(body["recommendations"] and isinstance(body["insights"], list))
        self.assertIsNone(body["assessment"]["forecast"])
        self.assertEqual(self.call("POST", "/api/farm/analyze", payload).status_code, 401)

    def test_flutter_pig_call_works_without_weight_classes(self):
        r = self.call("POST", "/api/pig/analyze", {"pig_id": "SYN-p", "birth_date": "2026-06-01",
                                                   "current_weight": 40.0, "birth_weight": 1.4}, USER)
        self.assertEqual(r.status_code, 200)
        self.assertIsNone(r.json()["classification"])
        self.assertIn("weight history", r.json()["insight"])


class Validation(APITest):
    def test_invalid_inputs_are_422(self):
        bad = [
            {"pen_id": "x", "readings": readings(dht_humidity_pct=150)},                 # impossible value
            {"pen_id": "x", "readings": []},                                              # empty
            {"pen_id": "x", "readings": readings(n=api_config()["limits"]["max_readings"] + 1)},
            {"pen_id": "x", "readings": [{**readings()[0], "timestamp": "2026-10-19T05:59:00"}]},  # no tz
            {"pen_id": "x", "readings": readings(), "unexpected": 1},                    # unknown field
        ]
        for b in bad:
            self.assertEqual(self.call("POST", "/assess/environment", b, USER).status_code, 422)
        r = self.call("POST", "/assess/pig-growth",
                      {"pig": {"birth_date": "2026-06-01"}, "weights": [{"date": "2026-07-01", "weight_kg": 0}]}, USER)
        self.assertEqual(r.status_code, 422)

    def test_request_body_limit_is_413(self):
        big = b"{" + b" " * (api_config()["limits"]["max_request_bytes"] + 10) + b"}"
        self.assertEqual(self.call("POST", "/assess/environment", raw=big, token=USER).status_code, 413)
        self.assertEqual(self.call("POST", "/assess/environment", raw=big, token=USER,
                                   send_length=False).status_code, 413)

    def test_valid_environment_schema(self):
        r = self.env()
        self.assertEqual(r.status_code, 200, r.content)
        b = r.json()
        for k in ("output", "method", "reasons", "inputs_summary", "data_quality_status",
                  "data_quality_warnings", "model_version", "timestamp", "forecast"):
            self.assertIn(k, b)
        self.assertEqual(b["output"]["status"], "heat_risk")
        self.assertEqual(b["data_quality_status"], "ok")
        self.assertTrue(all(i["source"] == "sensor" for i in b["inputs_summary"] if i["name"].startswith("dht")))
        self.assertNotRegex(json.dumps(b).lower(), r'"(probability|confidence)"')


class FailSafe(APITest):
    def test_no_model_returns_rule_result_with_null_forecast(self):
        b = self.env().json()
        self.assertIsNone(b["forecast"])
        self.assertIsNone(b["model_version"])
        self.assertEqual(b["method"], "rule")
        self.assertTrue(any("no approved forecast model" in w for w in b["data_quality_warnings"]))

    def test_active_model_gives_forecast(self):
        make_version(self.root, "SYN-v1", offset=1.5)
        self.start()
        self.assertEqual(self.call("POST", "/models/SYN-v1/activate", token=ADMIN).status_code, 200)
        b = self.env().json()
        self.assertEqual(b["method"], "rule+ML")
        self.assertEqual(b["model_version"], "SYN-v1")
        self.assertAlmostEqual(b["forecast"]["value"], round(82.92 + 1.5, 2), places=2)
        self.assertIn("not a probability", b["forecast"]["note"])

    def test_stale_offline_future_and_sparse_inputs_withhold_forecast(self):
        make_version(self.root, "SYN-v1", offset=1.5)
        self.start()
        self.call("POST", "/models/SYN-v1/activate", token=ADMIN)
        cases = {
            "stale": readings(end=NOW - timedelta(minutes=10)),
            "offline": readings(dht_temp_valid=False),
            "invalid": readings(end=NOW + timedelta(minutes=10)),
        }
        for dq, rs in cases.items():
            b = self.env(rs).json()
            self.assertEqual(b["data_quality_status"], dq, dq)
            self.assertIsNone(b["forecast"], dq)
            self.assertIsNone(b["model_version"], dq)
        stale = self.env(cases["stale"]).json()
        self.assertEqual(stale["output"]["status"], "heat_risk")             # rule result still returned
        sparse = self.env(readings(n=3)).json()
        self.assertIsNone(sparse["forecast"])
        self.assertTrue(any("look-back" in w for w in sparse["data_quality_warnings"]))
        no_mist = [{k: v for k, v in r.items() if k != "sprinkler_on"} for r in readings()]
        self.assertIsNone(self.env(no_mist).json()["forecast"])              # imputer may not invent state

    def test_model_load_failure_at_startup(self):
        make_version(self.root, "SYN-broken", offset=0, corrupt=True)
        (self.root / "ACTIVE.json").write_text(json.dumps({"active": "SYN-broken", "previous": None}))
        self.start()
        b = self.env().json()
        self.assertIsNone(b["forecast"])
        self.assertTrue(any("failed to load" in w for w in b["data_quality_warnings"]))
        ready = self.call("GET", "/ready")
        self.assertEqual(ready.json()["checks"]["forecast_model"], "load_failed")
        self.assertTrue(ready.json()["degraded"])

    def test_refused_activations_leave_pointer_unchanged(self):
        make_version(self.root, "SYN-good", offset=1.0)
        make_version(self.root, "SYN-broken", offset=0, corrupt=True)
        make_version(self.root, "SYN-candidate", offset=2.0, status="candidate")
        self.start()
        self.call("POST", "/models/SYN-good/activate", token=ADMIN)
        before = (self.root / "ACTIVE.json").read_text()
        for v, code in (("SYN-broken", 409), ("SYN-candidate", 409), ("nope", 404), ("..%2Fx", 400)):
            self.assertEqual(self.call("POST", f"/models/{v}/activate", token=ADMIN).status_code, code, v)
        self.assertEqual((self.root / "ACTIVE.json").read_text(), before)
        self.assertEqual(self.env().json()["model_version"], "SYN-good")

    def test_synthetic_model_refused_when_not_allowed(self):
        make_version(self.root, "SYN-v1", offset=1.0)
        self.reg_cfg["allow_synthetic_models"] = False
        self.start()
        r = self.call("POST", "/models/SYN-v1/activate", token=ADMIN)
        self.assertEqual(r.status_code, 409)
        self.assertIn("synthetic", r.json()["detail"])


class VersionSwitch(APITest):
    def test_switch_and_rollback_load_once_per_activation(self):
        make_version(self.root, "SYN-A", offset=1.0)
        make_version(self.root, "SYN-B", offset=3.0)
        self.start()
        loads = mock.patch.object(registry_mod.joblib, "load", wraps=joblib.load)
        with loads as spy:
            self.call("POST", "/models/SYN-A/activate", token=ADMIN)
            for _ in range(3):
                self.assertAlmostEqual(self.env().json()["forecast"]["value"], 83.92, places=2)
            self.assertEqual(spy.call_count, 1)                              # not per request
            r = self.call("POST", "/models/SYN-B/activate", token=ADMIN).json()
            self.assertEqual((r["pointer"]["active"], r["pointer"]["previous"]), ("SYN-B", "SYN-A"))
            self.assertAlmostEqual(self.env().json()["forecast"]["value"], 85.92, places=2)
            r = self.call("POST", "/models/rollback", token=ADMIN).json()
            self.assertEqual(r["activated"], "SYN-A")
            self.assertAlmostEqual(self.env().json()["forecast"]["value"], 83.92, places=2)
            self.assertEqual(spy.call_count, 3)
        self.assertEqual(json.loads((self.root / "ACTIVE.json").read_text())["previous"], "SYN-B")

    def test_pointer_write_is_atomic(self):
        make_version(self.root, "SYN-A", offset=1.0)
        make_version(self.root, "SYN-B", offset=3.0)
        self.start()
        self.call("POST", "/models/SYN-A/activate", token=ADMIN)
        before = (self.root / "ACTIVE.json").read_text()
        with mock.patch.object(registry_mod.os, "replace", side_effect=OSError("disk full")):
            r = self.call("POST", "/models/SYN-B/activate", token=ADMIN)
        self.assertEqual(r.status_code, 500)
        self.assertEqual((self.root / "ACTIVE.json").read_text(), before)
        self.assertEqual(list(self.root.glob(".ACTIVE-*")), [])               # temp file cleaned up
        self.assertEqual(self.env().json()["model_version"], "SYN-A")       # in-memory model unchanged

    def test_rollback_without_previous(self):
        self.assertEqual(self.call("POST", "/models/rollback", token=ADMIN).status_code, 409)


class Authorization(APITest):
    ADMIN_ROUTES = [("GET", "/models"), ("GET", "/models/active"), ("GET", "/models/SYN-A/evaluation"),
                    ("POST", "/models/SYN-A/activate"), ("POST", "/models/rollback")]

    def test_admin_routes_need_admin(self):
        make_version(self.root, "SYN-A", offset=1.0)
        self.start()
        for m, p in self.ADMIN_ROUTES:
            self.assertEqual(self.call(m, p).status_code, 401, p)
            self.assertEqual(self.call(m, p, token="SYN-forged").status_code, 401, p)
            self.assertEqual(self.call(m, p, token=USER).status_code, 403, p)
        self.assertEqual(self.call("GET", "/models", token=ADMIN).status_code, 200)
        info = self.call("GET", "/models/SYN-A/evaluation", token=ADMIN).json()
        self.assertEqual(info["metrics"]["mae"], 0.1)
        self.assertNotIn("joblib", json.dumps(self.call("GET", "/models", token=ADMIN).json()))

    def test_assessments_need_a_signed_in_user(self):
        for p, body in (("/assess/environment", {"readings": readings()}),
                        ("/assess/pig-growth", {"pig": {"birth_date": "2026-06-01"}, "weights": []}),
                        ("/assess/pen-thermal", {"current": {"timestamp": NOW.isoformat()}})):
            self.assertEqual(self.call("POST", p, body).status_code, 401, p)
            self.assertEqual(self.call("POST", p, body, USER).status_code, 200, p)

    def test_auth_not_configured_fails_closed(self):
        self.start(verifier=None)
        self.assertEqual(self.call("POST", "/assess/environment", {"readings": readings()}, USER).status_code, 503)
        self.assertEqual(self.call("GET", "/models", token=ADMIN).status_code, 503)
        self.assertEqual(self.call("GET", "/ready").status_code, 503)
        self.assertEqual(self.call("GET", "/health").status_code, 200)

    def test_tokens_never_logged(self):
        secret = "SYN-secret-token-value-123"
        with self.assertLogs("prism", level="INFO") as logs:
            self.call("GET", "/models", token=secret)
            self.call("GET", "/models", token=USER)
            self.call("POST", "/assess/environment", {"readings": readings()}, USER)
        text = "\n".join(logs.output)
        for tok in (secret, USER, ADMIN):
            self.assertNotIn(tok, text)
        self.assertIn("token rejected", text)


class OtherEndpoints(APITest):
    def test_pig_growth_and_pen_thermal(self):
        w = [{"date": d, "weight_kg": kg, "source": "manual"} for d, kg in
             (("2026-07-01", 10.0), ("2026-07-08", 13.5), ("2026-07-15", 17.0), ("2026-07-22", 20.5))]
        b = self.call("POST", "/assess/pig-growth", {"pig": {"pig_id": "SYN", "birth_date": "2026-06-01"},
                                                    "weights": w}, USER).json()
        self.assertEqual((b["output"]["status"], b["method"], b["model_version"]), ("no_flags", "rule", None))
        cur = {"timestamp": (NOW - timedelta(seconds=5)).isoformat(), "amg_summary_c": 33.0, "dht_temp_c": 29.0}
        hist = [{"timestamp": (NOW - timedelta(hours=1, minutes=30 * i)).isoformat(),
                 "amg_summary_c": 32.0 + ((i % 5) - 2) * 0.1, "dht_temp_c": 29.0} for i in range(40)]
        b = self.call("POST", "/assess/pen-thermal", {"pen_id": "SYN", "current": cur, "history": hist}, USER).json()
        self.assertEqual((b["output"]["status"], b["method"]), ("unusual", "statistical"))
        stale = {**cur, "timestamp": (NOW - timedelta(minutes=5)).isoformat()}
        b = self.call("POST", "/assess/pen-thermal", {"current": stale, "history": hist}, USER).json()
        self.assertEqual((b["output"]["status"], b["data_quality_status"]), ("unavailable", "stale"))


class NoSprinklerControl(unittest.TestCase):
    def test_api_code_has_no_path_to_the_sprinkler(self):
        app_dir = Path(__file__).resolve().parent.parent / "app"
        for f in app_dir.glob("*.py"):
            src = f.read_text(encoding="utf-8")
            for pattern in (r"sprinkler_command", r"/sprinkler\b", r"\bimport (requests|httpx|urllib)",
                            r"firestore\.client", r"\.set\(\{"):
                self.assertIsNone(re.search(pattern, src), f"{f.name}: {pattern}")
        paths = list(create_app().openapi()["paths"])
        self.assertFalse([p for p in paths if "sprinkler" in p or "pump" in p or "command" in p])


if __name__ == "__main__":
    unittest.main()


class RegisterDecision(unittest.TestCase):
    """First half of the evaluation gate: only real data + a passing acceptance rule pass."""
    from forecast.report import INVALID, VALID
    OK = {"validity": VALID, "acceptance": {"allowed": True, "horizon_minutes": 60, "candidate": "random_forest"}}

    def test_report_gate(self):
        from forecast.register import report_gate
        self.assertTrue(report_gate(self.OK, 60, "random_forest", False)[0])
        self.assertFalse(report_gate(self.OK, 60, "random_forest", True)[0])                  # synthetic
        self.assertFalse(report_gate({**self.OK, "validity": self.INVALID}, 60, "random_forest", False)[0])
        self.assertFalse(report_gate(self.OK, 30, "random_forest", False)[0])                 # other horizon
        self.assertFalse(report_gate(self.OK, 60, "decision_tree", False)[0])                 # other model
        no = {**self.OK, "acceptance": {"allowed": False, "reason": "no acceptance_rule"}}
        self.assertFalse(report_gate(no, 60, "random_forest", False)[0])


class RuleConfigForApp(APITest):
    def test_rule_config_for_offline_fallback(self):
        self.assertEqual(self.call("GET", "/config/rules").status_code, 401)
        b = self.call("GET", "/config/rules", token=USER).json()
        self.assertEqual(b["thi"]["categories"]["Grower"]["thresholds"], [74.0, 79.0])   # synthetic test cfg
        self.assertIn("T", b["thi"]["formula"])
        self.assertNotIn("model", json.dumps(b).lower().replace("models", ""))


class TokenClockSkew(unittest.TestCase):
    def test_verifier_allows_configured_clock_skew(self):
        from app.auth import FirebaseVerifier
        v = object.__new__(FirebaseVerifier)              # skip Firebase initialisation
        v._auth = mock.Mock()
        v.verify("SYN-token")
        v._auth.verify_id_token.assert_called_once_with(
            "SYN-token", clock_skew_seconds=api_config()["auth"]["clock_skew_seconds"])
        self.assertTrue(0 < api_config()["auth"]["clock_skew_seconds"] <= 60)   # Firebase maximum


class RejectionReasonLogging(APITest):
    def test_reason_is_logged_without_the_token(self):
        jwt = "SYNaaaaaaaaaaaa.SYNbbbbbbbbbbbbbb.SYNcccccccccc"

        class Rejecting:
            def verify(self, token):
                raise ValueError(f'Firebase ID token has incorrect "aud" claim; token {token}')

        self.start(verifier=Rejecting())
        with self.assertLogs("prism.api.auth", level="WARNING") as logs:
            self.assertEqual(self.call("GET", "/models", token=jwt).status_code, 401)
        text = "\n".join(logs.output)
        self.assertIn('incorrect "aud" claim', text)          # the useful reason is there
        self.assertNotIn(jwt, text)                           # the token is not
        self.assertIn("[token removed]", text)


class VerifierNeedsNoServiceAccount(unittest.TestCase):
    """Regression: firebase-admin 7.x raised DefaultCredentialsError on every token when no
    service account was configured, so the app's sign-in was always rejected."""

    def test_public_keys_only_credential(self):
        from google.auth.credentials import AnonymousCredentials
        from app.auth import _public_keys_only_credential
        self.assertIsInstance(_public_keys_only_credential().get_credential(), AnonymousCredentials)

    def test_initialised_without_service_account(self):
        import firebase_admin
        from app.auth import FirebaseVerifier
        env = {"PRISM_FIREBASE_PROJECT": "SYN-project"}
        with mock.patch.dict("os.environ", env, clear=False), \
                mock.patch.dict("os.environ", {}, clear=False) as e, \
                mock.patch.object(firebase_admin, "_apps", {}), \
                mock.patch.object(firebase_admin, "initialize_app") as init, \
                mock.patch.object(firebase_admin, "get_app") as get_app:
            e.pop("GOOGLE_APPLICATION_CREDENTIALS", None)
            get_app.return_value.project_id = "SYN-project"
            FirebaseVerifier()
        cred = init.call_args.kwargs["credential"]
        self.assertIsNotNone(cred)                        # not left to application-default lookup
        self.assertEqual(init.call_args.kwargs["options"], {"projectId": "SYN-project"})
