import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path

from fastapi.testclient import TestClient

from prism_ml.api.main import create_app
from prism_ml.api.repository import SQLiteRepository
from prism_ml.api.settings import Settings
from prism_ml.data.local_dataset import READING_COLUMNS
from prism_ml.models.inference import Assessor
from prism_ml.models.registry import ModelRegistry
from test_api import AUTH, DEVICE_SECRET, fake_verifier, payload, signed_headers

ML = Path(__file__).resolve().parent.parent


def client_with(repo, tmp_path):
    s = Settings(device_secrets={"esp-a": {"secret": DEVICE_SECRET, "farm_id": "farm-a"}})
    app = create_app(settings=s, assessor=Assessor(ModelRegistry(tmp_path / "art")), verifier=fake_verifier,
                     repository=repo)
    return TestClient(app, raise_server_exceptions=False)


def test_sqlite_ingest_isolation_and_latest(tmp_path):
    repo = SQLiteRepository(tmp_path / "store.sqlite3")
    repo.add_member("farm-a", "alice")
    c = client_with(repo, tmp_path)
    older = payload(observed_at=(datetime.now(timezone.utc) - timedelta(seconds=30)).isoformat(), air_temp_c=20.0)
    newer = payload(observed_at=(datetime.now(timezone.utc) - timedelta(seconds=2)).astimezone(
        timezone(timedelta(hours=8))).isoformat(), air_temp_c=31.0)  # +08:00 offset, still the newest
    for p in (newer, older):
        body = json.dumps(p).encode()
        assert c.post("/v1/devices/esp-a/readings", content=body, headers=signed_headers(body)).status_code == 200
    r = c.get("/v1/farms/farm-a/assessment/latest", headers=AUTH)
    assert r.status_code == 200 and r.json()["measurements"]["air_temp_c"] == 31.0
    assert c.get("/v1/farms/farm-a/assessment/latest", headers={"Authorization": "Bearer token-bob"}).status_code == 403
    repo.remove_member("farm-a", "alice")
    assert c.get("/v1/farms/farm-a/assessment/latest", headers=AUTH).status_code == 403


def test_sqlite_export_produces_loader_format(tmp_path):
    db = tmp_path / "store.sqlite3"
    repo = SQLiteRepository(db)
    repo.store_reading("farm-a", "esp-a", payload(), {"ok": True})
    import importlib.util
    spec = importlib.util.spec_from_file_location("export_readings", ML / "scripts" / "export_readings.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    os.environ["PRISM_SQLITE_PATH"] = str(db)
    try:
        rows = [mod.to_row(rid, dev, "farm-a", d) for rid, dev, d in mod._rows_sqlite("farm-a")]
    finally:
        del os.environ["PRISM_SQLITE_PATH"]
    assert len(rows) == 1 and list(rows[0]) == READING_COLUMNS and rows[0]["data_origin"] == "farm"
    assert len(json.loads(rows[0]["thermal_pixels_c"])) == 64
