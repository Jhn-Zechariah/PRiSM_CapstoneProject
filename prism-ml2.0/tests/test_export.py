"""Export tests on the SYNTHETIC fixture tests/fixtures/SYNTHETIC_sensor_readings.jsonl."""
import importlib.util
import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

from pipeline.export import export, main, read_jsonl

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "SYNTHETIC_sensor_readings.jsonl"
NOW = datetime(2026, 10, 20, tzinfo=timezone.utc)


class ExportFixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.raw = read_jsonl(FIXTURE)

    def tearDown(self):
        self.tmp.cleanup()

    def test_csv_export_keeps_every_record_with_flags_and_version(self):
        target, manifest = export(self.raw, self.tmp.name, now=NOW, input_desc="fixture")
        df = pd.read_csv(target / "readings.csv")
        self.assertEqual(len(df), len(self.raw))            # nothing dropped
        for col in ("dataset_version", "record_id", "quality", "quality_flags",
                    "dht_humidity_pct__state", "amg_summary_c", "source", "schema_version"):
            self.assertIn(col, df.columns)
        self.assertTrue((df["dataset_version"] == manifest["dataset_version"]).all())
        self.assertTrue(manifest["dataset_version"].startswith("SYNTHETIC-"))
        self.assertTrue(manifest["contains_synthetic"])
        self.assertEqual(manifest["record_count"], len(self.raw))

        by = df.set_index("record_id")
        self.assertIn("impossible:dht_humidity_pct", by.loc["SYN-r003", "quality_flags"])
        self.assertEqual(by.loc["SYN-r004", "dht_humidity_pct__state"], "sensor_offline")
        self.assertEqual(by.loc["SYN-r005", "dht_humidity_pct__state"], "missing")
        self.assertIn("stale_timestamp:ntp_unsynced", by.loc["SYN-r006", "quality_flags"])
        self.assertIn("duplicate:same_device_time", by.loc["SYN-r007", "quality_flags"])
        self.assertIn("after_offline", by.loc["SYN-r008", "quality_flags"])
        self.assertIn("timestamp_not_firestore_type:string", by.loc["SYN-r009", "quality_flags"])
        v2 = by.loc["SYN-pen1-esp32-1792368920"]
        self.assertEqual(v2["quality"], "ok", v2["quality_flags"])
        self.assertEqual(len(json.loads(v2["amg_pixels_c"])), 64)

        periods = pd.read_csv(target / "offline_periods.csv")
        self.assertEqual(len(periods), 1)
        self.assertEqual(manifest["offline_period_count"], 1)
        self.assertEqual(read_jsonl(target / "raw_snapshot.jsonl"), self.raw)

    def test_version_is_deterministic_and_changes_with_data(self):
        _, m1 = export(self.raw, self.tmp.name, now=NOW)
        _, m2 = export(self.raw, self.tmp.name, now=NOW)
        self.assertEqual(m1["dataset_version"], m2["dataset_version"])
        changed = json.loads(json.dumps(self.raw))
        changed[0]["data"]["ambientHumidity"] = 79.9
        _, m3 = export(changed, self.tmp.name, now=NOW)
        self.assertNotEqual(m1["dataset_version"], m3["dataset_version"])

    def test_corrections_file_is_applied(self):
        corr = {"correctionId": "SYN-r003__v1", "recordId": "SYN-r003", "version": 1,
                "fields": {"dht_humidity_pct": 80.0}, "reason": "SYN test", "author": "SYN",
                "source": "manual", "createdAt": "2026-10-19T01:00:00+00:00", "schemaVersion": 2}
        target, manifest = export(self.raw, self.tmp.name, corrections=[corr], now=NOW)
        df = pd.read_csv(target / "readings.csv").set_index("record_id")
        self.assertEqual(df.loc["SYN-r003", "dht_humidity_pct"], 130.0)
        self.assertEqual(df.loc["SYN-r003", "dht_humidity_pct__corrected"], 80.0)
        self.assertEqual(manifest["corrections_applied"], 1)

    def test_cli_file_mode(self):
        main(["--input", str(FIXTURE), "--out", self.tmp.name, "--now", NOW.isoformat()])
        self.assertEqual(len(list(Path(self.tmp.name).glob("SYNTHETIC-*/readings.csv"))), 1)

    @unittest.skipUnless(importlib.util.find_spec("pyarrow"), "pyarrow not installed")
    def test_parquet_export(self):
        target, _ = export(self.raw, self.tmp.name, fmt="parquet", now=NOW)
        self.assertEqual(len(pd.read_parquet(target / "readings.parquet")), len(self.raw))


if __name__ == "__main__":
    unittest.main()
