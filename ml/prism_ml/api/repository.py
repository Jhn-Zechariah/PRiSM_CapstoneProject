"""Storage for device-submitted readings and farm membership.

Backends: ``sqlite`` (self-hosted, free, recommended), ``firestore`` (subject to Spark quotas),
``memory`` (tests/dev), ``none``.

Firestore layout used by :class:`FirestoreRepository` (see docs/DEPLOYMENT.md and firestore.rules)::

    farms/{farmId}                       { memberUids: [uid, ...], name, ... }
    farms/{farmId}/sensor_readings/{id}  validated reading + data-quality report + deviceId + receivedAt

Only the API (service account) writes ``sensor_readings``; app users can read their own farm's readings.
"""
from __future__ import annotations

import threading
import uuid
from datetime import datetime, timezone
from typing import Optional, Protocol


class StorageUnavailable(RuntimeError):
    pass


class Repository(Protocol):
    def store_reading(self, farm_id: str, device_id: str, reading: dict, quality: dict) -> str: ...

    def latest_reading(self, farm_id: str) -> Optional[dict]: ...

    def is_member(self, farm_id: str, uid: str) -> bool: ...


class NoStorage:
    """Default when no storage backend is configured: farm-scoped endpoints are unavailable."""

    def store_reading(self, farm_id, device_id, reading, quality):
        raise StorageUnavailable()

    def latest_reading(self, farm_id):
        raise StorageUnavailable()

    def is_member(self, farm_id, uid):
        raise StorageUnavailable()


class InMemoryRepository:
    """Used by the automated tests and for local development without Firestore."""

    def __init__(self, members: Optional[dict[str, set[str]]] = None):
        self.members = members or {}
        self.readings: dict[str, list[dict]] = {}
        self._lock = threading.Lock()

    def store_reading(self, farm_id, device_id, reading, quality):
        rid = uuid.uuid4().hex
        with self._lock:
            self.readings.setdefault(farm_id, []).append(
                {"id": rid, "device_id": device_id, "reading": reading, "quality": quality,
                 "received_at": datetime.now(timezone.utc).isoformat()})
        return rid

    def latest_reading(self, farm_id):
        rows = self.readings.get(farm_id) or []
        return max(rows, key=lambda r: r["reading"]["observed_at"])["reading"] if rows else None

    def is_member(self, farm_id, uid):
        return uid in self.members.get(farm_id, set())


class FirestoreRepository:
    TIMEOUT = 5.0

    def __init__(self):
        import firebase_admin
        from firebase_admin import firestore

        if not firebase_admin._apps:  # credentials from GOOGLE_APPLICATION_CREDENTIALS / workload identity
            firebase_admin.initialize_app()
        self.db = firestore.client()

    def store_reading(self, farm_id, device_id, reading, quality):
        ref = self.db.collection("farms").document(farm_id).collection("sensor_readings").document()
        ref.set({**reading, "deviceId": device_id, "quality": quality,
                 "receivedAt": datetime.now(timezone.utc)}, timeout=self.TIMEOUT)
        return ref.id

    def latest_reading(self, farm_id):
        q = (self.db.collection("farms").document(farm_id).collection("sensor_readings")
             .order_by("observed_at", direction="DESCENDING").limit(1))
        docs = list(q.stream(timeout=self.TIMEOUT))
        if not docs:
            return None
        d = docs[0].to_dict()
        return {k: v for k, v in d.items() if k not in ("deviceId", "quality", "receivedAt")}

    def is_member(self, farm_id, uid):
        snap = self.db.collection("farms").document(farm_id).get(timeout=self.TIMEOUT)
        return snap.exists and uid in (snap.to_dict() or {}).get("memberUids", [])


class SQLiteRepository:
    """Self-hosted storage (Python standard library, no external service, no quota, no billing).

    Recommended free-only backend: device readings and farm membership live in one SQLite file on the
    machine running the API (back it up; see docs/COST_AND_DEPENDENCIES.md). Manage members with
    ``scripts/farms.py``.
    """

    SCHEMA = """
    CREATE TABLE IF NOT EXISTS farm_members (farm_id TEXT NOT NULL, uid TEXT NOT NULL, PRIMARY KEY (farm_id, uid));
    CREATE TABLE IF NOT EXISTS sensor_readings (
        id TEXT PRIMARY KEY, farm_id TEXT NOT NULL, device_id TEXT NOT NULL, observed_at TEXT NOT NULL,
        received_at TEXT NOT NULL, reading_json TEXT NOT NULL, quality_json TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS ix_readings_farm_time ON sensor_readings (farm_id, observed_at);
    """

    def __init__(self, path):
        import sqlite3
        from pathlib import Path

        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self._sqlite3 = sqlite3
        self.path = str(path)
        self._lock = threading.Lock()
        with self._connect() as c:
            c.executescript(self.SCHEMA)

    def _connect(self):
        return self._sqlite3.connect(self.path, timeout=5)

    def store_reading(self, farm_id, device_id, reading, quality):
        import json

        rid = uuid.uuid4().hex
        observed = reading["observed_at"]
        if isinstance(observed, str):
            observed = datetime.fromisoformat(observed)
        observed = observed.astimezone(timezone.utc).isoformat()  # uniform UTC text sorts chronologically
        with self._lock, self._connect() as c:
            c.execute("INSERT INTO sensor_readings VALUES (?,?,?,?,?,?,?)",
                      (rid, farm_id, device_id, observed, datetime.now(timezone.utc).isoformat(),
                       json.dumps(reading, default=str), json.dumps(quality, default=str)))
        return rid

    def latest_reading(self, farm_id):
        import json

        with self._connect() as c:
            row = c.execute("SELECT reading_json FROM sensor_readings WHERE farm_id=? ORDER BY observed_at DESC LIMIT 1",
                            (farm_id,)).fetchone()
        return json.loads(row[0]) if row else None

    def is_member(self, farm_id, uid):
        with self._connect() as c:
            return c.execute("SELECT 1 FROM farm_members WHERE farm_id=? AND uid=?", (farm_id, uid)).fetchone() is not None

    def add_member(self, farm_id: str, uid: str) -> None:
        with self._lock, self._connect() as c:
            c.execute("INSERT OR IGNORE INTO farm_members VALUES (?,?)", (farm_id, uid))

    def remove_member(self, farm_id: str, uid: str) -> None:
        with self._lock, self._connect() as c:
            c.execute("DELETE FROM farm_members WHERE farm_id=? AND uid=?", (farm_id, uid))

    def export_readings(self, farm_id: str):
        import json

        with self._connect() as c:
            for rid, device_id, reading_json in c.execute(
                    "SELECT id, device_id, reading_json FROM sensor_readings WHERE farm_id=? ORDER BY observed_at",
                    (farm_id,)):
                yield rid, device_id, json.loads(reading_json)


def make_repository(backend: str, sqlite_path: str = "") -> Repository:
    if backend == "sqlite":
        from prism_ml.config import DATA_DIR

        return SQLiteRepository(sqlite_path or DATA_DIR / "local_store" / "prism.sqlite3")
    if backend == "firestore":
        return FirestoreRepository()
    if backend == "memory":
        return InMemoryRepository()
    return NoStorage()
