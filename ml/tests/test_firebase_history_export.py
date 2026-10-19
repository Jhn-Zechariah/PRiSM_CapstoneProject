"""Export path for the current firmware's Firestore history (sensor_readings_seconds).

The documents below are SYNTHETIC TEST FIXTURES shaped like the firmware's history writes; they only
exercise field mapping and loading, and are written to a temporary directory (never used for training).
"""
import csv
import importlib.util
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pandas as pd

from fixtures import frame
from prism_ml.data.local_dataset import LABEL_COLUMNS, READING_COLUMNS, load_local_dataset

ML = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("export_readings", ML / "scripts" / "export_readings.py")
exp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exp)

T0 = datetime(2026, 12, 1, 6, 0, tzinfo=timezone.utc)


def history_doc(i, with_frame=True):
    d = {"timestamp": T0 + timedelta(seconds=10 * i), "pigBodyTemp": 35.1, "ambientTemp": 29.0,
         "ambientHumidity": 78.0}
    if with_frame:
        d["thermalPixels"] = frame(35.1, 29.0)
    return d


def test_history_doc_mapping():
    row = exp.history_doc_to_row("s1", history_doc(0), "farm-1", "pen-1", "cal-2026-11")
    assert list(row) == READING_COLUMNS
    assert row["air_temp_c"] == 29.0 and row["air_temp_valid"] == "true"
    assert row["relative_humidity_pct"] == 78.0 and row["thermal_valid"] == "true"
    assert row["calibration_profile"] == "cal-2026-11" and row["data_origin"] == "farm"
    no_frame = exp.history_doc_to_row("s2", history_doc(1, with_frame=False), "farm-1", "pen-1", "")
    assert no_frame["thermal_valid"] == "" and no_frame["thermal_pixels_c"] == ""
    missing_air = history_doc(2)
    del missing_air["ambientTemp"]
    assert exp.history_doc_to_row("s3", missing_air, "farm-1", "pen-1", "")["air_temp_valid"] == ""


def test_label_windows_and_loader_end_to_end(tmp_path):
    root = tmp_path / "local"
    (root / "labels").mkdir(parents=True)
    (root / "readings").mkdir()
    label = {c: "" for c in LABEL_COLUMNS}
    label.update(label_session_id="S1", farm_id="farm-1", pen_id="pen-1", window_start=T0.isoformat(),
                 window_end=(T0 + timedelta(minutes=10)).isoformat(), status="Needs Attention",
                 label_confidence="confirmed", reviewer_id="vet-1", reviewer_role="veterinarian",
                 reviewer_blinded="true", protocol_version="PRISM-LABEL-1.0")
    other_pen = dict(label, label_session_id="S2", pen_id="pen-2")
    pd.DataFrame([label, other_pen], columns=LABEL_COLUMNS).to_csv(root / "labels" / "l.csv", index=False)

    windows = exp.label_windows("farm-1", "pen-1", root / "labels")
    assert windows == [(T0, T0 + timedelta(minutes=10))]

    rows = [exp.history_doc_to_row(f"s{i}", history_doc(i, with_frame=(i != 3)), "farm-1", "pen-1", "")
            for i in range(6)]
    with (root / "readings" / "r.csv").open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=READING_COLUMNS)
        w.writeheader()
        w.writerows(rows)
    ds = load_local_dataset(root)
    assert ds.summary["labeled_readings"] == 5                      # the frame-less reading is excluded
    assert ds.summary["readings_rejected_by_quality_layer"] == {"missing_value": 1}
    assert set(ds.frame["status"]) == {"Needs Attention"}
