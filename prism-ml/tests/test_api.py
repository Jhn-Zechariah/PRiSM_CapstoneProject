"""API tests with the Firestore client replaced by an in-memory fake (no network, no credentials)."""
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

import api
from common import AMB, HUM, PIG, envelope
from features import feature_columns

NOW = datetime(2026, 10, 26, 6, 0, tzinfo=timezone.utc)
KEY = "test-key"


# ----------------------------------------------------------------------------- fake Firestore
class FakeSnap:
    def __init__(self, data):
        self._d, self.exists = data, data is not None

    def to_dict(self):
        return dict(self._d)


class FakeDocRef:
    def __init__(self, data):
        self.data = data

    def get(self):
        return FakeSnap(self.data)


class FakeQuery:
    def __init__(self, store, name, filters=(), lim=None):
        self.store, self.name, self.filters, self.lim = store, name, list(filters), lim

    def where(self, filter):
        return FakeQuery(self.store, self.name, self.filters + [filter], self.lim)

    def order_by(self, field, direction=None):
        return self

    def limit(self, n):
        return FakeQuery(self.store, self.name, self.filters, n)

    def stream(self):
        ops = {">": lambda a, b: a > b, "<": lambda a, b: a < b, ">=": lambda a, b: a >= b}
        docs = sorted(self.store.docs.get(self.name, []), key=lambda d: d["timestamp"])
        for f in self.filters:
            docs = [d for d in docs if ops[f.op_string](d[f.field_path], f.value)]
        docs = docs[: self.lim] if self.lim else docs
        self.store.reads += max(1, len(docs))
        return [FakeSnap(d) for d in docs]


class FakeCollection(FakeQuery):
    def document(self, doc_id):
        return FakeDocRef(self.store.single.get((self.name, doc_id)))


class FakeClient:
    def __init__(self):
        self.docs, self.single, self.reads = {}, {}, 0

    def collection(self, name):
        return FakeCollection(self, name)


def readings(minutes, end=NOW, pig=33.0, amb=28.0, hum=80.0):
    """10-second docs covering the `minutes` before `end`."""
    out = []
    t = end - timedelta(minutes=minutes)
    while t <= end:
        out.append({"timestamp": t, PIG: pig, AMB: amb, HUM: hum})
        t += timedelta(seconds=10)
    return out


def persistence_bundle(cfg):
    return {"model_name": "persistence", "version": "persistence-test", "data_source": "synthetic",
            "synthetic_only": True, "trained_at": NOW.isoformat(), "feature_columns": feature_columns(cfg),
            "estimators": {15: None, 30: None}, "envelope": envelope(cfg)}


@pytest.fixture
def make_client(cfg, monkeypatch):
    monkeypatch.setenv("PRISM_API_KEY", KEY)

    def _make(docs, clock=lambda: NOW, live=None, logs=()):
        fake = FakeClient()
        fake.docs[cfg["firestore"]["readings_collection"]] = docs
        fake.docs[cfg["firestore"]["sprinkler_logs_collection"]] = list(logs)
        fake.single[(cfg["firestore"]["live_collection"], cfg["firestore"]["live_document"])] = live or {"sprinkler": False}
        app = api.create_app(source=api.FirestoreSource(fake, cfg), bundle=persistence_bundle(cfg),
                             clock=clock, cfg=cfg)
        return TestClient(app), fake
    return _make


def get(client):
    return client.get("/predict", headers={"X-API-Key": KEY})


def test_requires_api_key(make_client):
    client, _ = make_client(readings(60))
    assert client.get("/predict").status_code == 401
    assert client.get("/predict", headers={"X-API-Key": "wrong"}).status_code == 401
    assert client.get("/health").status_code == 200


def test_ok_prediction(make_client):
    client, _ = make_client(readings(60))
    r = get(client)
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert body["predicted_pig_temp_15min_c"] == pytest.approx(33.0)   # persistence model
    assert body["risk_level"] == "Good"
    assert body["latest_reading_at"].startswith("2026-10-26T06:00")
    assert body["current"]["sprinkler_on"] is False


def test_insufficient_when_no_data(make_client):
    client, _ = make_client([])
    assert get(client).json()["status"] == "insufficient_data"


def test_insufficient_when_window_too_short(make_client):
    client, _ = make_client(readings(10))
    body = get(client).json()
    assert body["status"] == "insufficient_data"
    assert body["predicted_pig_temp_15min_c"] is None


def test_stale_data(make_client):
    client, _ = make_client(readings(50, end=NOW - timedelta(minutes=10)))
    body = get(client).json()
    assert body["status"] == "stale_data"
    assert body["risk_level"] is None


def test_out_of_training_range(make_client):
    client, _ = make_client(readings(60, amb=40.0))
    body = get(client).json()
    assert body["status"] == "out_of_training_range"
    assert body["predicted_pig_temp_15min_c"] is None
    assert "ambientTemp" in body["message"]


def test_cache_and_incremental_reads(make_client, cfg):
    now = {"t": NOW}
    docs = readings(60)
    client, fake = make_client(docs, clock=lambda: now["t"])
    get(client)
    first_reads = fake.reads
    assert first_reads >= 361                       # cold start reads the hour once

    body = get(client).json()                        # within cache TTL: no Firestore reads
    assert body["cached"] is True and fake.reads == first_reads

    # after the TTL: only the 6 new docs (+ live doc) are read, not the whole hour again
    app_state = client.app.state.prism
    app_state["cache"] = (app_state["cache"][0] - cfg["api"]["cache_ttl_s"] - 1, app_state["cache"][1])
    now["t"] = NOW + timedelta(minutes=1)
    docs += [{"timestamp": NOW + timedelta(seconds=10 * k), PIG: 33.0, AMB: 28.0, HUM: 80.0} for k in range(1, 7)]
    body = get(client).json()
    assert body["status"] == "ok" and body["cached"] is False
    assert fake.reads - first_reads <= 8


def test_sprinkler_state_from_live_doc(make_client):
    client, _ = make_client(readings(60), live={"sprinkler": True})
    body = get(client).json()
    assert body["current"]["sprinkler_on"] is True
    assert "sprinkler is currently running" in body["recommendation"]
