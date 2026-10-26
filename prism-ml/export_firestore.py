"""Export historical sensor readings (and sprinkler logs) from Firestore to local parquet.

    python export_firestore.py --start 2026-10-01                 # first export
    python export_firestore.py                                    # resume from the last exported reading
    python export_firestore.py --start 2026-10-01 --end 2026-10-08 --yes

Cost control:
  * one cheap COUNT aggregation first (about 1 read per 1,000 documents); if the export
    would read more than `export.warn_above_docs` documents it stops unless --yes is given
  * documents are read once, in timestamp order, page by page; each page is saved
    immediately to data/real/readings_parts/, so an interrupted export resumes where it stopped
"""
from __future__ import annotations

import argparse
import sys
from datetime import datetime, timezone

import pandas as pd

from common import AMB, HUM, PIG, REAL_PARTS_DIR, SPRINKLER_LOGS_PATH, get_firestore_client, load_config


def _local_date(s: str, tz: str) -> datetime:
    return pd.Timestamp(s, tz=tz).tz_convert("UTC").to_pydatetime()


def last_exported_timestamp():
    parts = sorted(REAL_PARTS_DIR.glob("*.parquet")) if REAL_PARTS_DIR.exists() else []
    if not parts:
        return None
    return max(pd.read_parquet(p, columns=["timestamp"])["timestamp"].max() for p in parts).to_pydatetime()


def export_readings(db, cfg, start, end, page_size, assume_yes) -> int:
    from google.cloud.firestore_v1.base_query import FieldFilter
    fs = cfg["firestore"]
    ts = fs["timestamp_field"]
    col = db.collection(fs["readings_collection"])

    def base_query(after):
        q = col.where(filter=FieldFilter(ts, ">", after))
        if end is not None:
            q = q.where(filter=FieldFilter(ts, "<", end))
        return q

    n = base_query(start).count(alias="n").get()[0][0].value
    print(f"Documents to export: {n:,} (from {start.isoformat()} to {end.isoformat() if end else 'now'})")
    if n > cfg["export"]["warn_above_docs"] and not assume_yes:
        print(f"WARNING: this export would read about {n:,} documents "
              f"(more than {cfg['export']['warn_above_docs']:,}). Re-run with --yes to proceed, "
              "or narrow --start/--end.")
        sys.exit(2)
    if n == 0:
        return 0

    REAL_PARTS_DIR.mkdir(parents=True, exist_ok=True)
    after, total = start, 0
    while True:
        q = base_query(after).order_by(ts).limit(page_size).select([ts, PIG, AMB, HUM])
        rows = []
        for d in q.stream():
            r = d.to_dict()
            rows.append({"timestamp": r.get(ts), PIG: r.get(PIG), AMB: r.get(AMB), HUM: r.get(HUM), "doc_id": d.id})
        if not rows:
            break
        df = pd.DataFrame(rows)
        df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True)
        for c in (PIG, AMB, HUM):
            df[c] = pd.to_numeric(df[c], errors="coerce")
        first, last = df["timestamp"].min(), df["timestamp"].max()
        df.to_parquet(REAL_PARTS_DIR / f"readings_{int(first.timestamp())}_{int(last.timestamp())}.parquet",
                      index=False)
        total += len(df)
        print(f"  saved {total:,}/{n:,} (up to {last.isoformat()})")
        after = last.to_pydatetime()
        if len(rows) < page_size:
            break
    return total


def export_sprinkler_logs(db, cfg) -> int:
    from google.cloud.firestore_v1.base_query import FieldFilter
    fs = cfg["firestore"]
    ts = fs["timestamp_field"]
    old = pd.read_parquet(SPRINKLER_LOGS_PATH) if SPRINKLER_LOGS_PATH.exists() else None
    q = db.collection(fs["sprinkler_logs_collection"])
    if old is not None and len(old):
        q = q.where(filter=FieldFilter(ts, ">", old["timestamp"].max().to_pydatetime()))
    rows = [{"timestamp": r.get(ts), "durationSec": r.get("durationSec"), "type": r.get("type")}
            for r in (d.to_dict() for d in q.order_by(ts).stream())]
    if not rows:
        return 0
    new = pd.DataFrame(rows)
    new["timestamp"] = pd.to_datetime(new["timestamp"], utc=True)
    new["durationSec"] = pd.to_numeric(new["durationSec"], errors="coerce").fillna(0)
    out = pd.concat([old, new]) if old is not None else new
    SPRINKLER_LOGS_PATH.parent.mkdir(parents=True, exist_ok=True)
    out.drop_duplicates("timestamp").sort_values("timestamp").to_parquet(SPRINKLER_LOGS_PATH, index=False)
    return len(new)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--start", help="local date YYYY-MM-DD (default: resume after the last exported reading)")
    ap.add_argument("--end", help="local date YYYY-MM-DD, exclusive (default: now)")
    ap.add_argument("--yes", action="store_true", help="proceed even above the read-count warning")
    ap.add_argument("--no-resume", action="store_true", help="ignore already exported data")
    a = ap.parse_args()
    cfg = load_config()
    tz = cfg["project"]["timezone"]

    start = None if a.no_resume else last_exported_timestamp()
    if start is not None:
        print(f"Resuming after {start.isoformat()}")
    elif a.start:
        start = _local_date(a.start, tz)
    else:
        sys.exit("First export: pass --start YYYY-MM-DD")
    end = _local_date(a.end, tz) if a.end else None

    db = get_firestore_client()
    n = export_readings(db, cfg, start, end, cfg["export"]["page_size"], a.yes)
    m = export_sprinkler_logs(db, cfg)
    print(f"Done: {n:,} readings, {m:,} new sprinkler log entries ({datetime.now(timezone.utc).isoformat()})")


if __name__ == "__main__":
    main()
