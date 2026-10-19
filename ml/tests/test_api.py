import json
import secrets
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from fixtures import frame
from prism_ml.api.auth import TokenVerificationError, sign
from prism_ml.api.main import create_app
from prism_ml.api.repository import InMemoryRepository
from prism_ml.api.settings import Settings
from prism_ml.models.inference import Assessor
from prism_ml.models.registry import ModelRegistry

TOKENS = {"token-alice": "alice", "token-bob": "bob"}
DEVICE_SECRET = "d" * 40
CONTRACT_DIR = Path(__file__).parent / "contract"


def fake_verifier(token):
    if token not in TOKENS:
        raise TokenVerificationError("bad")
    return {"sub": TOKENS[token]}


def payload(**kw):
    p = {"schema_version": "1", "observed_at": (datetime.now(timezone.utc) - timedelta(seconds=3)).isoformat(),
         "air_temp_c": 29.5, "air_temp_valid": True, "relative_humidity_pct": 78.0, "humidity_valid": True,
         "thermal_pixels_c": frame(35.0, 29.0), "thermal_valid": True, "water_level_pct": 60.0, "water_valid": True}
    p.update(kw)
    return p


@pytest.fixture
def repo():
    return InMemoryRepository(members={"farm-a": {"alice"}, "farm-b": {"bob"}})


def make_client(tmp_path, repo=None, **settings_kw):
    s = Settings(**{"device_secrets": {"esp-a": {"secret": DEVICE_SECRET, "farm_id": "farm-a"}}, **settings_kw})
    app = create_app(settings=s, assessor=Assessor(ModelRegistry(tmp_path / "art")), verifier=fake_verifier,
                     repository=repo or InMemoryRepository())
    return TestClient(app, raise_server_exceptions=False)


@pytest.fixture
def client(tmp_path, repo):
    return make_client(tmp_path, repo)


AUTH = {"Authorization": "Bearer token-alice"}


def signed_headers(body: bytes, path="/v1/devices/esp-a/readings", device="esp-a", secret=DEVICE_SECRET, ts=None,
                   nonce=None):
    ts = str(int(time.time()) if ts is None else ts)
    nonce = nonce or secrets.token_hex(12)
    return {"Content-Type": "application/json", "X-PRISM-Device": device, "X-PRISM-Timestamp": ts,
            "X-PRISM-Nonce": nonce, "X-PRISM-Signature": sign(secret, ts, nonce, "POST", path, body)}


# ------------------------------------------------------------------ basics / hardening
def test_health_and_security_headers(client):
    r = client.get("/health")
    assert r.status_code == 200 and r.json() == {"status": "ok"}
    assert r.headers["x-content-type-options"] == "nosniff" and r.headers["cache-control"] == "no-store"


def test_docs_disabled_by_default(client):
    assert client.get("/docs").status_code == 404 and client.get("/openapi.json").status_code == 404


def test_hsts_in_production(tmp_path):
    c = make_client(tmp_path, env="production", firebase_project_id="demo-project")
    assert "strict-transport-security" in c.get("/health").headers


# ------------------------------------------------------------------ user authentication
def test_missing_token_401(client):
    r = client.post("/v1/assessments", json=payload())
    assert r.status_code == 401 and r.json()["error"] == "authentication_required"


def test_invalid_token_401(client):
    r = client.post("/v1/assessments", json=payload(), headers={"Authorization": "Bearer nope"})
    assert r.status_code == 401 and r.json()["error"] == "invalid_token"


def test_repeated_auth_failures_are_blocked(tmp_path):
    c = make_client(tmp_path, auth_fail_limit=3)
    for _ in range(3):
        assert c.post("/v1/assessments", json=payload(), headers={"Authorization": "Bearer x"}).status_code == 401
    assert c.post("/v1/assessments", json=payload(), headers=AUTH).status_code == 429


def test_auth_not_configured_returns_503(tmp_path):
    app = create_app(settings=Settings(), assessor=Assessor(ModelRegistry(tmp_path)), verifier=None)
    r = TestClient(app).post("/v1/assessments", json=payload(), headers=AUTH)
    assert r.status_code == 503


# ------------------------------------------------------------------ assessments
def test_valid_assessment(client):
    r = client.post("/v1/assessments", json=payload(), headers=AUTH)
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "Classification Unavailable" and body["status_kind"] == "operational"
    assert body["insights"] and body["disclaimer"] and body["feature_contract_version"] == "1.0.0"


def test_stale_and_missing_data(client):
    old = (datetime.now(timezone.utc) - timedelta(minutes=10)).isoformat()
    assert client.post("/v1/assessments", json=payload(observed_at=old), headers=AUTH).json()["status"] == "Insufficient Data"
    assert client.post("/v1/assessments", json=payload(air_temp_c=None), headers=AUTH).json()["status"] == "Insufficient Data"
    assert client.post("/v1/assessments", json=payload(thermal_valid=False), headers=AUTH).json()["status"] == \
        "Sensor Check Required"


@pytest.mark.parametrize("body", [
    {"observed_at": "not-a-date"},
    {"thermal_pixels_c": [30.0] * 65},
    {"unexpected_field": 1},
    {"schema_version": "2"},
    {"air_temp_c": "hot"},
])
def test_invalid_bodies_rejected_safely(client, body):
    r = client.post("/v1/assessments", json=payload(**body), headers=AUTH)
    assert r.status_code == 422
    text = r.text
    assert r.json()["error"] == "invalid_request" and "input" not in text and "hot" not in text and "Traceback" not in text


def test_non_json_rejected(client):
    r = client.post("/v1/assessments", content=b"a=b", headers={**AUTH, "Content-Type": "application/x-www-form-urlencoded"})
    assert r.status_code == 415


def test_oversized_body_rejected(tmp_path):
    c = make_client(tmp_path, max_body_bytes=2000)
    r = c.post("/v1/assessments", content=json.dumps(payload(notes="x" * 5000)), headers={**AUTH, "Content-Type": "application/json"})
    assert r.status_code == 413


def test_user_rate_limit(tmp_path):
    c = make_client(tmp_path, rate_limit_per_minute=2)
    codes = [c.post("/v1/assessments", json=payload(), headers=AUTH).status_code for _ in range(3)]
    assert codes == [200, 200, 429]


def test_model_endpoint(client):
    r = client.get("/v1/model", headers=AUTH)
    assert r.status_code == 200 and r.json()["available"] is False and r.json()["reason"] == "no_approved_model"


def test_model_load_failure_reported(tmp_path):
    reg = ModelRegistry(tmp_path / "art")
    (tmp_path / "art").mkdir()
    (tmp_path / "art" / "registry.json").write_text(json.dumps(
        {"approved": "ghost-model", "models": {"ghost-model": {"sha256": {"model.joblib": "0" * 64}}}, "history": []}))
    app = create_app(settings=Settings(), assessor=Assessor(reg), verifier=fake_verifier)
    c = TestClient(app)
    assert c.get("/v1/model", headers=AUTH).json()["reason"] == "model_load_failed"
    assert c.post("/v1/assessments", json=payload(), headers=AUTH).json()["reason"] == "model_load_failed"


def test_unhandled_error_is_generic(tmp_path, monkeypatch):
    c = make_client(tmp_path)
    monkeypatch.setattr(c.app.state.assessor, "assess", lambda *_a, **_k: (_ for _ in ()).throw(RuntimeError("secret-path")))
    r = c.post("/v1/assessments", json=payload(), headers=AUTH)
    assert r.status_code == 500 and r.json()["error"] == "internal_error" and "secret-path" not in r.text


# ------------------------------------------------------------------ farm isolation
def test_cross_farm_access_forbidden(client, repo):
    repo.store_reading("farm-b", "esp-b", payload(), {})
    r = client.get("/v1/farms/farm-b/assessment/latest", headers=AUTH)  # alice is not a member of farm-b
    assert r.status_code == 403


def test_member_gets_latest_assessment(client, repo):
    repo.store_reading("farm-a", "esp-a", payload(observed_at=datetime.now(timezone.utc)), {})
    r = client.get("/v1/farms/farm-a/assessment/latest", headers=AUTH)
    assert r.status_code == 200 and r.json()["status"] == "Classification Unavailable"


def test_no_readings_404(client):
    assert client.get("/v1/farms/farm-a/assessment/latest", headers=AUTH).status_code == 404


def test_storage_failure_503(client, repo, monkeypatch):
    monkeypatch.setattr(repo, "is_member", lambda *_: (_ for _ in ()).throw(TimeoutError("firestore down")))
    r = client.get("/v1/farms/farm-a/assessment/latest", headers=AUTH)
    assert r.status_code == 503 and "firestore" not in r.text


def test_storage_not_configured_503(tmp_path):
    app = create_app(settings=Settings(), assessor=Assessor(ModelRegistry(tmp_path)), verifier=fake_verifier)
    assert TestClient(app).get("/v1/farms/farm-a/assessment/latest", headers=AUTH).status_code == 503


# ------------------------------------------------------------------ device ingestion
def test_device_ingest_signed(client, repo):
    body = json.dumps(payload()).encode()
    r = client.post("/v1/devices/esp-a/readings", content=body, headers=signed_headers(body))
    assert r.status_code == 200 and r.json()["accepted"] is True and r.json()["stored"] is True
    assert len(repo.readings["farm-a"]) == 1 and repo.readings["farm-a"][0]["device_id"] == "esp-a"
    assert "farm-b" not in repo.readings


def test_device_ingest_stores_rejected_quality_but_flags_it(client, repo):
    body = json.dumps(payload(thermal_valid=False)).encode()
    r = client.post("/v1/devices/esp-a/readings", content=body, headers=signed_headers(body))
    assert r.status_code == 200 and r.json()["accepted"] is False


def test_device_bad_signature(client):
    body = json.dumps(payload()).encode()
    r = client.post("/v1/devices/esp-a/readings", content=body, headers=signed_headers(body, secret="x" * 40))
    assert r.status_code == 401


def test_device_tampered_body(client):
    body = json.dumps(payload()).encode()
    h = signed_headers(body)
    r = client.post("/v1/devices/esp-a/readings", content=json.dumps(payload(air_temp_c=20.0)).encode(), headers=h)
    assert r.status_code == 401


def test_device_replay_rejected(client):
    body = json.dumps(payload()).encode()
    h = signed_headers(body, nonce="fixed-nonce-123456")
    assert client.post("/v1/devices/esp-a/readings", content=body, headers=h).status_code == 200
    assert client.post("/v1/devices/esp-a/readings", content=body, headers=h).status_code == 401


def test_device_old_timestamp_rejected(client):
    body = json.dumps(payload()).encode()
    r = client.post("/v1/devices/esp-a/readings", content=body, headers=signed_headers(body, ts=int(time.time()) - 3600))
    assert r.status_code == 401


def test_unknown_device_rejected(client):
    body = json.dumps(payload()).encode()
    h = signed_headers(body, path="/v1/devices/esp-z/readings", device="esp-z")
    assert client.post("/v1/devices/esp-z/readings", content=body, headers=h).status_code == 401


def test_device_cannot_post_as_another_device(client):
    body = json.dumps(payload()).encode()
    # Valid esp-a credentials, but targeting esp-b's path: signature covers the path, so it fails.
    h = signed_headers(body, path="/v1/devices/esp-b/readings")
    assert client.post("/v1/devices/esp-b/readings", content=body, headers=h).status_code == 403


def test_device_id_in_body_must_match(client):
    body = json.dumps(payload(device_id="esp-b")).encode()
    r = client.post("/v1/devices/esp-a/readings", content=body, headers=signed_headers(body))
    assert r.status_code == 422


def test_user_token_cannot_ingest(client):
    r = client.post("/v1/devices/esp-a/readings", json=payload(), headers=AUTH)
    assert r.status_code == 401


# ------------------------------------------------------------------ mobile contract
def test_response_matches_mobile_contract(client):
    """The Flutter client (lib/core/services/ml_service.dart) parses exactly these fields."""
    request = json.loads((CONTRACT_DIR / "assessment_request_example.json").read_text())
    request["observed_at"] = datetime.now(timezone.utc).isoformat()
    body = client.post("/v1/assessments", json=request, headers=AUTH).json()
    expected = json.loads((CONTRACT_DIR / "assessment_response_keys.json").read_text())
    assert set(expected["top_level"]) <= set(body)
    for item in body["insights"]:
        assert set(expected["insight"]) <= set(item)
    for item in body["references"]:
        assert set(expected["reference"]) <= set(item)
    assert body["status"] in expected["status_values"]
