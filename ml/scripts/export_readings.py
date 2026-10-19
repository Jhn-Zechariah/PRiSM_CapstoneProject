"""Export stored device readings into data/raw/local/readings/ (training input format).

    python scripts/export_readings.py --farm <farmId>                      # self-hosted SQLite (default, free)
    python scripts/export_readings.py --farm <farmId> --source firestore   # farms/{farmId}/sensor_readings
    python scripts/export_readings.py --farm <farmId> --pen <penId> --source firebase-history
                                     # current firmware's sensor_readings_seconds, label windows only

``firebase-history`` reads ONLY the time windows of the reviewer label sessions found in
data/raw/local/labels/*.csv (for the given farm and pen), so a whole month of sessions costs a few
thousand Firestore reads instead of 8,640 per day of history (free Spark quota: 50,000 reads/day).
Each history document must contain the full 64-pixel ``thermalPixels`` frame (firmware change in
docs/HOW_TO_TRAIN_WITH_FIREBASE_DATA.txt); documents without it are exported with the frame missing and
are then excluded by the data-quality layer.

Exported rows are NOT labels. Labels come only from reviewer label sessions (data/raw/local/labels/),
never from model predictions.
"""
import argparse
import csv
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from prism_ml.config import RAW_LOCAL_DIR  # noqa: E402
from prism_ml.data.local_dataset import GENUINE_ORIGIN, READING_COLUMNS  # noqa: E402


def _rows_sqlite(farm: str):
    from prism_ml.api.repository import make_repository

    yield from make_repository("sqlite", os.environ.get("PRISM_SQLITE_PATH", "")).export_readings(farm)


def _rows_firestore(farm: str):
    import firebase_admin
    from firebase_admin import firestore

    if not firebase_admin._apps:
        firebase_admin.initialize_app()
    q = firestore.client().collection("farms").document(farm).collection("sensor_readings").order_by("observed_at")
    for doc in q.stream(timeout=60):
        d = doc.to_dict()
        yield doc.id, d.get("deviceId") or d.get("device_id"), d


def label_windows(farm: str, pen: str, labels_dir: Path) -> list[tuple[datetime, datetime]]:
    import pandas as pd

    files = sorted(Path(labels_dir).glob("*.csv"))
    if not files:
        return []
    df = pd.concat([pd.read_csv(f, dtype=str, keep_default_na=False) for f in files], ignore_index=True)
    df = df[(df["farm_id"] == farm) & (df["pen_id"] == pen)]
    starts = pd.to_datetime(df["window_start"], utc=True, errors="coerce")
    ends = pd.to_datetime(df["window_end"], utc=True, errors="coerce")
    return [(a.to_pydatetime(), b.to_pydatetime()) for a, b in zip(starts, ends) if pd.notna(a) and pd.notna(b)]


def history_doc_to_row(doc_id: str, d: dict, farm: str, pen: str, calibration_profile: str) -> dict:
    """Map one firmware ``sensor_readings_seconds`` document to a training-input row.

    The firmware writes a value only when it was valid, so a present value means valid and an absent
    one is exported as missing (the data-quality layer then rejects that reading).
    """
    px = d.get("thermalPixels")
    has_frame = isinstance(px, list) and len(px) == 64
    ts = d["timestamp"]
    return {
        "reading_id": doc_id, "device_id": d.get("deviceId") or pen, "farm_id": farm, "pen_id": pen,
        "observed_at": ts.isoformat() if hasattr(ts, "isoformat") else ts,
        "air_temp_c": d.get("ambientTemp"), "air_temp_valid": "true" if "ambientTemp" in d else "",
        "relative_humidity_pct": d.get("ambientHumidity"),
        "humidity_valid": "true" if "ambientHumidity" in d else "",
        "thermal_pixels_c": json.dumps(px) if has_frame else "", "thermal_valid": "true" if has_frame else "",
        "water_level_pct": "", "water_valid": "",
        "calibration_profile": d.get("calibrationProfile") or calibration_profile, "data_origin": GENUINE_ORIGIN,
    }


def _rows_firebase_history(farm: str, pen: str, collection: str, windows, calibration_profile: str):
    import firebase_admin
    from firebase_admin import firestore

    if not firebase_admin._apps:
        firebase_admin.initialize_app()
    col = firestore.client().collection(collection)
    for start, end in windows:
        q = col.where("timestamp", ">=", start).where("timestamp", "<=", end)
        for doc in q.stream(timeout=60):
            yield history_doc_to_row(doc.id, doc.to_dict(), farm, pen, calibration_profile)


def to_row(rid: str, device_id: str, farm: str, d: dict) -> dict:
    ts = d["observed_at"]
    return {
        "reading_id": rid, "device_id": device_id, "farm_id": farm, "pen_id": d.get("pen_id") or device_id,
        "observed_at": ts.isoformat() if hasattr(ts, "isoformat") else ts,
        "air_temp_c": d.get("air_temp_c"), "air_temp_valid": d.get("air_temp_valid"),
        "relative_humidity_pct": d.get("relative_humidity_pct"), "humidity_valid": d.get("humidity_valid"),
        "thermal_pixels_c": json.dumps(d.get("thermal_pixels_c")), "thermal_valid": d.get("thermal_valid"),
        "water_level_pct": d.get("water_level_pct"), "water_valid": d.get("water_valid"),
        "calibration_profile": d.get("calibration_profile"), "data_origin": GENUINE_ORIGIN,
    }


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--farm", required=True)
    p.add_argument("--source", choices=["sqlite", "firestore", "firebase-history"], default="sqlite")
    p.add_argument("--pen", help="pen id used in the label sheets (firebase-history only)")
    p.add_argument("--collection", default="sensor_readings_seconds", help="firebase-history collection")
    p.add_argument("--labels-dir", type=Path, default=RAW_LOCAL_DIR / "labels")
    p.add_argument("--calibration-profile", default="",
                   help="calibration profile active during collection, if the documents do not carry one")
    args = p.parse_args()

    if args.source == "firebase-history":
        if not args.pen:
            p.error("--pen is required with --source firebase-history")
        windows = label_windows(args.farm, args.pen, args.labels_dir)
        if not windows:
            print(f"No label sessions for farm={args.farm} pen={args.pen} in {args.labels_dir}; nothing exported.")
            return 2
        print(f"Exporting {len(windows)} label-session windows from '{args.collection}'...")
        rows = _rows_firebase_history(args.farm, args.pen, args.collection, windows, args.calibration_profile)
    else:
        src = _rows_sqlite(args.farm) if args.source == "sqlite" else _rows_firestore(args.farm)
        rows = (to_row(rid, device_id, args.farm, d) for rid, device_id, d in src)

    out_dir = RAW_LOCAL_DIR / "readings"
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"{args.source}_{args.farm}_{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}.csv"
    n = no_frame = 0
    with out.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=READING_COLUMNS)
        w.writeheader()
        for row in rows:
            w.writerow(row)
            n += 1
            no_frame += row["thermal_valid"] in ("", None)
    print(f"wrote {n} readings to {out}")
    if no_frame:
        print(f"WARNING: {no_frame} readings have no 64-pixel thermal frame and will be excluded from training.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
