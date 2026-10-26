"""Confirm the Firestore connection works.

Reads ONE recent sensor document (plus live_sensor/latest) and prints only field
names and value types - never values, never credentials. About 2 document reads.

    python check_connection.py
"""
from __future__ import annotations

from common import get_firestore_client, load_config


def describe(title: str, data: dict | None):
    print(f"\n{title}")
    if not data:
        print("  (no document found)")
        return
    for k in sorted(data):
        v = data[k]
        kind = type(v).__name__
        if isinstance(v, list):
            kind += f"[{len(v)}]"
        print(f"  {k:24s} {kind}")


def main():
    cfg = load_config()
    fs = cfg["firestore"]
    db = get_firestore_client()
    print("Connected to Cloud Firestore.")
    q = (db.collection(fs["readings_collection"])
         .order_by(fs["timestamp_field"], direction="DESCENDING").limit(1))
    docs = list(q.stream())
    describe(f"{fs['readings_collection']} (latest document)", docs[0].to_dict() if docs else None)
    snap = db.collection(fs["live_collection"]).document(fs["live_document"]).get()
    describe(f"{fs['live_collection']}/{fs['live_document']}", snap.to_dict() if snap.exists else None)


if __name__ == "__main__":
    main()
