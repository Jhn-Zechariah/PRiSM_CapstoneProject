"""Maps a raw Firestore sensor document (schema v1 or v2) to canonical columns.

The raw document is never changed. Field names come from config/sensor_schema.json.
"""
import json
from datetime import datetime, timezone

TS_TAG = "__timestamp__"   # how a Firestore Timestamp is written in our JSONL dumps


def parse_time(value):
    """Returns (aware UTC datetime or None, type label)."""
    if value is None:
        return None, "missing"
    if isinstance(value, dict) and TS_TAG in value:
        dt, _ = parse_time(value[TS_TAG])
        return dt, "firestore_timestamp"
    if isinstance(value, datetime):          # includes Firestore DatetimeWithNanoseconds
        dt = value if value.tzinfo else value.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc), "firestore_timestamp"
    if isinstance(value, bool):
        return None, "invalid"
    if isinstance(value, (int, float)):
        secs = value / 1000.0 if value > 1e11 else float(value)   # epoch ms vs s
        try:
            return datetime.fromtimestamp(secs, tz=timezone.utc), "epoch_number"
        except (OverflowError, OSError, ValueError):
            return None, "invalid"
    if isinstance(value, str):
        try:
            dt = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
        except ValueError:
            return None, "invalid"
        dt = dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc), "string"
    return None, "invalid"


def _number(v):
    if isinstance(v, bool) or v is None:
        return None
    if isinstance(v, (int, float)):
        return float(v)
    return None


def _bool(v):
    return v if isinstance(v, bool) else None


def _coerce(value, ftype):
    if ftype == "number":
        return _number(value)
    if ftype == "bool":
        return _bool(value)
    if ftype == "int":
        return int(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else None
    if ftype == "string":
        return value if isinstance(value, str) else None
    if ftype == "number_array":
        if not isinstance(value, list):
            return None
        return [_number(x) for x in value]
    return value


def normalize(record_id, data, schema, ingest_time=None):
    """One raw document -> one canonical dict. Keeps a copy of the raw payload."""
    data = data or {}
    out = {"record_id": record_id}

    ingest_dt, _ = parse_time(ingest_time)
    out["ingest_time_utc"] = ingest_dt

    known = set()
    for col, spec in schema["record_fields"].items():
        fs = spec["firestore"]
        known.add(fs)
        if col == "timestamp_utc":
            dt, kind = parse_time(data.get(fs))
            out["timestamp_utc"] = dt
            out["timestamp_type"] = kind
            raw = data.get(fs)
            out["timestamp_raw"] = raw.get(TS_TAG) if isinstance(raw, dict) else (
                raw.isoformat() if isinstance(raw, datetime) else raw)
            continue
        out[col] = _coerce(data.get(fs), spec["type"])

    if out.get("schema_version") is None:
        out["schema_version"] = schema["record_fields"]["schema_version"]["default_when_absent"]
        out["schema_version_inferred"] = True
    else:
        out["schema_version_inferred"] = False

    if out.get("source") is None:
        out["source"] = schema["default_source"]
        out["source_inferred"] = True
    else:
        out["source_inferred"] = False

    for ch, spec in schema["channels"].items():
        fs = spec["firestore"]
        known.add(fs)
        out[f"{ch}__present"] = fs in data and data[fs] is not None
        out[ch] = _coerce(data.get(fs), spec["type"])
        vf = spec.get("valid_field")
        if vf:
            known.add(vf)
            out[f"{ch}__valid"] = _bool(data.get(vf))   # None = firmware did not say

    out["synthetic"] = bool(data.get("_synthetic", False))
    known.add("_synthetic")
    extra = {k: v for k, v in data.items() if k not in known}
    out["extra_fields"] = json.dumps(extra, sort_keys=True, default=str) if extra else ""
    return out
