"""Versioned corrections for sensor records.

Raw observations are immutable. A correction is a separate document in the
`sensor_corrections` collection (name in config/sensor_schema.json) with the ID
"<record_id>__v<version>". Each version holds the COMPLETE set of corrected fields
for that record; the highest version wins. Exports keep the raw value and add
"<field>__corrected" next to it.
"""
from datetime import datetime, timezone


def correction_id(record_id, version):
    return f"{record_id}__v{int(version)}"


def make_correction(record_id, version, fields, reason, author, schema, created_at=None):
    if int(version) < 1:
        raise ValueError("version must be >= 1")
    if not fields:
        raise ValueError("a correction must change at least one field")
    bad = sorted(set(fields) - set(schema["correctable_fields"]))
    if bad:
        raise ValueError(f"not correctable: {bad}")
    if not reason or not author:
        raise ValueError("reason and author are required")
    return {
        "correctionId": correction_id(record_id, version),
        "recordId": record_id,
        "version": int(version),
        "fields": dict(fields),
        "reason": reason,
        "author": author,
        "source": "manual",
        "createdAt": (created_at or datetime.now(timezone.utc)).isoformat(),
        "schemaVersion": schema["schema_version"],
    }


def latest_by_record(corrections):
    latest = {}
    for c in corrections:
        cur = latest.get(c["recordId"])
        if cur is None or c["version"] > cur["version"]:
            latest[c["recordId"]] = c
    return latest


def apply_corrections(records, corrections, schema):
    """Returns copies of records with correction columns added. Raw columns are untouched."""
    latest = latest_by_record(corrections)
    fields = sorted({f for c in latest.values() for f in c["fields"]})
    out = []
    for rec in records:
        r = dict(rec)
        c = latest.get(r["record_id"])
        r["correction_version"] = c["version"] if c else 0
        r["correction_reason"] = c["reason"] if c else ""
        for f in fields:
            r[f"{f}__corrected"] = c["fields"].get(f, r.get(f)) if c else r.get(f)
        out.append(r)
    return out


def main(argv=None):
    """python -m pipeline.corrections --record-id ID --set dht_temp_c=30.1 --reason "..." --author NAME"""
    import argparse
    import json
    from pipeline import firestore_io
    from pipeline.config import load_schema

    p = argparse.ArgumentParser(description="Add a versioned correction (never edits the raw record).")
    p.add_argument("--record-id", required=True)
    p.add_argument("--set", action="append", required=True, metavar="FIELD=JSON_VALUE")
    p.add_argument("--reason", required=True)
    p.add_argument("--author", required=True)
    p.add_argument("--dry-run", action="store_true", help="print the document, do not write")
    a = p.parse_args(argv)

    schema = load_schema()
    fields = {}
    for item in a.set:
        k, _, v = item.partition("=")
        fields[k] = json.loads(v)
    coll = schema["corrections_collection"]
    existing = [] if a.dry_run else [c for c in firestore_io.fetch_corrections(coll)
                                     if c.get("recordId") == a.record_id]
    version = max((c["version"] for c in existing), default=0) + 1
    doc = make_correction(a.record_id, version, fields, a.reason, a.author, schema)
    if a.dry_run:
        print(json.dumps(doc, indent=2))
    else:
        print("created", coll, firestore_io.write_correction(coll, doc))


if __name__ == "__main__":
    main()
