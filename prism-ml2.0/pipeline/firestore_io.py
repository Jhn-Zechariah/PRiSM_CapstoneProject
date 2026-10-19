"""Firestore access for the pipeline.

Readings are only READ. Corrections are written with create(), which fails if the
document already exists, so a correction can never overwrite another one.

Credentials: never stored in the repo. Point GOOGLE_APPLICATION_CREDENTIALS at a
service-account JSON kept outside the repository (or use `gcloud auth
application-default login`). Install with: pip install -r requirements-data.txt
"""
import json
import os
from datetime import datetime

from pipeline.normalize import TS_TAG


def _client():
    try:
        import firebase_admin
        from firebase_admin import firestore
    except ImportError as e:
        raise SystemExit("firebase-admin is not installed. Run: pip install -r requirements-data.txt") from e
    if not firebase_admin._apps:
        project = os.environ.get("PRISM_FIREBASE_PROJECT")   # e.g. prism-3cd2c
        firebase_admin.initialize_app(options={"projectId": project} if project else None)
    return firestore.client()


def to_jsonable(v):
    """Firestore value -> JSON value. Timestamps keep their type via TS_TAG."""
    if isinstance(v, datetime):
        return {TS_TAG: v.isoformat()}
    if isinstance(v, dict):
        return {k: to_jsonable(x) for k, x in v.items()}
    if isinstance(v, list):
        return [to_jsonable(x) for x in v]
    if isinstance(v, (str, int, float, bool)) or v is None:
        return v
    return str(v)


def fetch_readings(collection, start=None, end=None, full_scan=False, page=1000):
    """Yields dicts {id, create_time, data}. A timestamp range query only finds docs whose
    `timestamp` is a Firestore Timestamp inside the range; use full_scan=True to also get
    docs with string or NTP-failed (1970) timestamps."""
    db = _client()
    q = db.collection(collection)
    if full_scan:
        q = q.order_by("__name__")
    else:
        if start is not None:
            q = q.where("timestamp", ">=", start)
        if end is not None:
            q = q.where("timestamp", "<", end)
        q = q.order_by("timestamp").order_by("__name__")
    last = None
    while True:
        qq = q.limit(page)
        if last is not None:
            qq = qq.start_after(last)
        docs = list(qq.stream())
        for d in docs:
            yield {"id": d.id,
                   "create_time": d.create_time.isoformat() if d.create_time else None,
                   "data": to_jsonable(d.to_dict())}
        if len(docs) < page:
            break
        last = docs[-1]


def fetch_corrections(collection):
    return [d.to_dict() for d in _client().collection(collection).stream()]


def write_correction(collection, correction):
    ref = _client().collection(collection).document(correction["correctionId"])
    ref.create(correction)       # raises AlreadyExists instead of overwriting
    return ref.id


def dump_jsonl(rows, path):
    with open(path, "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, sort_keys=True) + "\n")
