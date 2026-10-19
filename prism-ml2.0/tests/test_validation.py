"""Validation tests. ALL DATA HERE IS SYNTHETIC (built by synthetic_doc below).

Run:  python -m unittest discover -s tests -t .
"""
import copy
import unittest
from datetime import datetime, timedelta, timezone

from pipeline.config import load_schema, load_validation
from pipeline.corrections import apply_corrections, make_correction
from pipeline.normalize import TS_TAG, normalize
from pipeline.validate import validate

SCHEMA = load_schema()
VCFG = load_validation()
T0 = datetime(2026, 10, 19, 0, 0, 0, tzinfo=timezone.utc)
NOW = T0 + timedelta(days=1)


def synthetic_doc(offset_s=0, **overrides):
    """A SYNTHETIC schema-v1 document shaped like sensor_readings_seconds today."""
    d = {"timestamp": {TS_TAG: (T0 + timedelta(seconds=offset_s)).isoformat()},
         "pigBodyTemp": 31.5, "pigBodyTempValid": True,
         "ambientHumidity": 78.0, "ambientHumidityValid": True,
         "_synthetic": True}
    for k, v in overrides.items():
        if v is None:
            d.pop(k, None)
        else:
            d[k] = v
    return d


def run(docs, ingest_lag_s=1):
    """docs: list of (record_id, doc) or (record_id, doc, ingest_time)."""
    recs = []
    for item in docs:
        rid, doc = item[0], item[1]
        if len(item) > 2:
            ingest = item[2]
        else:
            ts = doc.get("timestamp")
            base = datetime.fromisoformat(ts[TS_TAG]) if isinstance(ts, dict) else T0
            ingest = (max(base, T0) + timedelta(seconds=ingest_lag_s)).isoformat()
        recs.append(normalize(rid, doc, SCHEMA, ingest))
    return validate(recs, VCFG, SCHEMA, now=NOW)


def flags(rec):
    return rec["quality_flags"]


class NormalReading(unittest.TestCase):
    def test_normal_v1_reading_is_ok(self):
        r = run([("SYN-a", synthetic_doc())]).records[0]
        self.assertEqual(r["quality"], "ok", flags(r))
        self.assertEqual(r["dht_humidity_pct__state"], "normal")
        self.assertEqual(r["amg_summary_c__state"], "normal")
        self.assertEqual(r["time_basis"], "device")

    def test_legacy_pigBodyTemp_maps_to_pen_level_amg_summary(self):
        r = run([("SYN-a", synthetic_doc())]).records[0]
        self.assertEqual(r["amg_summary_c"], 31.5)
        self.assertNotIn("pigBodyTemp", r)           # no per-pig column in the canonical record
        self.assertTrue(r["schema_version_inferred"])
        self.assertEqual(r["schema_version"], 1)
        self.assertTrue(r["source_inferred"])
        self.assertEqual(r["source"], "sensor")

    def test_fields_not_expected_in_v1_history_are_not_flagged_missing(self):
        r = run([("SYN-a", synthetic_doc())]).records[0]
        self.assertFalse([f for f in flags(r) if f.startswith("missing:")], flags(r))
        self.assertEqual(r["amg_thermistor_c__state"], "missing")   # state still says it
        self.assertEqual(r["dht_temp_c__state"], "missing")

    def test_v2_record_missing_a_channel_is_flagged(self):
        r = run([("SYN-a", synthetic_doc(schemaVersion=2))]).records[0]
        self.assertIn("missing:amg_thermistor_c", flags(r))


class InvalidValues(unittest.TestCase):
    def test_impossible_humidity_flagged_bad_but_kept(self):
        res = run([("SYN-a", synthetic_doc(ambientHumidity=130.0))])
        self.assertEqual(len(res.records), 1)
        r = res.records[0]
        self.assertIn("impossible:dht_humidity_pct", flags(r))
        self.assertEqual(r["quality"], "bad")
        self.assertEqual(r["dht_humidity_pct"], 130.0)    # raw value preserved

    def test_out_of_range_is_warn_not_bad(self):
        r = run([("SYN-a", synthetic_doc(ambientTemp=48.0, ambientTempValid=True))]).records[0]
        self.assertIn("out_of_range:dht_temp_c", flags(r))
        self.assertEqual(r["quality"], "warn")

    def test_wrong_type_is_impossible(self):
        r = run([("SYN-a", synthetic_doc(ambientHumidity="78"))]).records[0]
        self.assertIn("impossible:dht_humidity_pct:type", flags(r))

    def test_zero_humidity_is_sentinel(self):
        r = run([("SYN-a", synthetic_doc(ambientHumidity=0.0))]).records[0]
        self.assertIn("sentinel:dht_humidity_pct", flags(r))

    def test_frame_with_wrong_length_or_bad_pixel(self):
        short = run([("SYN-a", synthetic_doc(thermalPixels=[30.0] * 63))]).records[0]
        self.assertIn("invalid_frame:amg_pixels_c", flags(short))
        hot = run([("SYN-b", synthetic_doc(thermalPixels=[30.0] * 63 + [150.0]))]).records[0]
        self.assertIn("impossible:amg_pixels_c", flags(hot))
        ok = run([("SYN-c", synthetic_doc(thermalPixels=[30.0 + i * 0.01 for i in range(64)]))]).records[0]
        self.assertEqual(ok["amg_pixels_c__state"], "normal")


class OfflineVsMissingVsNormal(unittest.TestCase):
    def test_three_states_are_distinct(self):
        res = run([
            ("SYN-normal", synthetic_doc(0)),
            ("SYN-offline", synthetic_doc(10, ambientHumidity=0.0, ambientHumidityValid=False)),
            ("SYN-missing", synthetic_doc(20, ambientHumidity=None, ambientHumidityValid=None)),
        ])
        by = {r["record_id"]: r for r in res.records}
        self.assertEqual(by["SYN-normal"]["dht_humidity_pct__state"], "normal")
        self.assertEqual(by["SYN-offline"]["dht_humidity_pct__state"], "sensor_offline")
        self.assertIn("sensor_offline:dht_humidity_pct", flags(by["SYN-offline"]))
        self.assertNotIn("sentinel:dht_humidity_pct", flags(by["SYN-offline"]))  # value not judged
        self.assertEqual(by["SYN-missing"]["dht_humidity_pct__state"], "missing")
        self.assertIn("missing:dht_humidity_pct", flags(by["SYN-missing"]))
        self.assertEqual(by["SYN-missing"]["quality"], "ok")   # missing is info, not an error

    def test_device_offline_gap_creates_period(self):
        res = run([("SYN-a", synthetic_doc(0)), ("SYN-b", synthetic_doc(10)),
                   ("SYN-c", synthetic_doc(10 + 900))])
        by = {r["record_id"]: r for r in res.records}
        self.assertIn("after_offline", flags(by["SYN-c"]))
        self.assertEqual(by["SYN-c"]["prev_gap_s"], 900.0)
        self.assertEqual(len(res.offline_periods), 1)
        p = res.offline_periods[0]
        self.assertEqual((p["last_record_before"], p["first_record_after"]), ("SYN-b", "SYN-c"))

    def test_short_gap_is_missed_readings_not_offline(self):
        res = run([("SYN-a", synthetic_doc(0)), ("SYN-b", synthetic_doc(60))])
        self.assertIn("missed_readings", flags(res.records[1]))
        self.assertEqual(res.offline_periods, [])


class StaleAndMissingTimestamps(unittest.TestCase):
    def test_ntp_failed_epoch_is_stale_and_ordered_by_ingest(self):
        doc = synthetic_doc(timestamp={TS_TAG: "1970-01-01T00:00:00+00:00"})
        r = run([("SYN-a", doc, (T0 + timedelta(seconds=5)).isoformat())]).records[0]
        self.assertIn("stale_timestamp:ntp_unsynced", flags(r))
        self.assertEqual(r["quality"], "bad")
        self.assertEqual(r["time_basis"], "ingest")
        self.assertEqual(r["effective_time_utc"], T0 + timedelta(seconds=5))

    def test_future_timestamp(self):
        doc = synthetic_doc(timestamp={TS_TAG: (NOW + timedelta(hours=2)).isoformat()})
        r = run([("SYN-a", doc, NOW.isoformat())]).records[0]
        self.assertIn("stale_timestamp:future", flags(r))

    def test_large_ingest_lag_is_stale(self):
        r = run([("SYN-a", synthetic_doc(0), (T0 + timedelta(hours=1)).isoformat())]).records[0]
        self.assertIn("stale_timestamp:ingest_lag", flags(r))

    def test_buffered_replay_is_late_arrival_not_stale(self):
        doc = synthetic_doc(0, buffered=True)
        r = run([("SYN-a", doc, (T0 + timedelta(hours=1)).isoformat())]).records[0]
        self.assertIn("late_arrival", flags(r))
        self.assertFalse([f for f in flags(r) if f.startswith("stale_timestamp")])
        self.assertEqual(r["time_basis"], "device")

    def test_missing_and_unparseable_timestamp(self):
        res = run([("SYN-a", synthetic_doc(timestamp=None), T0.isoformat()),
                   ("SYN-b", synthetic_doc(timestamp="not a date"), T0.isoformat())])
        self.assertIn("missing_timestamp", flags(res.records[0]))
        self.assertIn("missing_timestamp:unparseable", flags(res.records[1]))

    def test_string_timestamp_is_noted(self):
        r = run([("SYN-a", synthetic_doc(timestamp=T0.isoformat()))]).records[0]
        self.assertIn("timestamp_not_firestore_type:string", flags(r))
        self.assertEqual(r["quality"], "ok")


class Duplicates(unittest.TestCase):
    def test_same_device_time_flags_later_copy_only(self):
        res = run([("SYN-a", synthetic_doc(0), (T0 + timedelta(seconds=1)).isoformat()),
                   ("SYN-b", synthetic_doc(0), (T0 + timedelta(seconds=3)).isoformat())])
        by = {r["record_id"]: r for r in res.records}
        self.assertEqual(len(res.records), 2)              # nothing removed
        self.assertNotIn("duplicate:same_device_time", flags(by["SYN-a"]))
        self.assertIn("duplicate:same_device_time", flags(by["SYN-b"]))
        self.assertEqual(by["SYN-b"]["duplicate_of"], "SYN-a")

    def test_same_record_id_twice(self):
        res = run([("SYN-a", synthetic_doc(0)), ("SYN-a", synthetic_doc(0))])
        self.assertEqual(sum("duplicate:same_id" in flags(r) for r in res.records), 1)

    def test_different_devices_same_time_are_not_duplicates(self):
        res = run([("SYN-a", synthetic_doc(0, deviceId="SYN-dev1")),
                   ("SYN-b", synthetic_doc(0, deviceId="SYN-dev2"))])
        self.assertFalse(any(f.startswith("duplicate") for r in res.records for f in flags(r)))


class StuckValues(unittest.TestCase):
    def test_constant_humidity_for_over_an_hour_is_stuck(self):
        docs = [(f"SYN-{i:04d}", synthetic_doc(i * 10, pigBodyTemp=31.0 + (i % 7) * 0.25))
                for i in range(400)]                      # 66 min of identical humidity
        res = run(docs)
        self.assertTrue(all("stuck:dht_humidity_pct" in flags(r) for r in res.records))
        self.assertFalse(any("stuck:amg_summary_c" in flags(r) for r in res.records))
        self.assertEqual(res.records[0]["dht_humidity_pct__state"], "flagged")

    def test_varying_values_are_not_stuck(self):
        docs = [(f"SYN-{i:04d}", synthetic_doc(i * 10, ambientHumidity=70 + (i % 5) * 0.3,
                                               pigBodyTemp=31.0 + (i % 7) * 0.25)) for i in range(400)]
        res = run(docs)
        self.assertFalse(any(f.startswith("stuck") for r in res.records for f in flags(r)))

    def test_short_constant_run_is_not_stuck(self):
        res = run([(f"SYN-{i}", synthetic_doc(i * 10)) for i in range(30)])   # 5 minutes
        self.assertFalse(any(f.startswith("stuck") for r in res.records for f in flags(r)))


class NonDestructive(unittest.TestCase):
    def test_input_records_are_not_modified(self):
        recs = [normalize("SYN-a", synthetic_doc(ambientHumidity=130.0), SCHEMA, T0.isoformat())]
        before = copy.deepcopy(recs)
        validate(recs, VCFG, SCHEMA, now=NOW)
        self.assertEqual(recs, before)

    def test_raw_doc_is_not_modified_by_normalize(self):
        doc = synthetic_doc()
        before = copy.deepcopy(doc)
        normalize("SYN-a", doc, SCHEMA, T0.isoformat())
        self.assertEqual(doc, before)


class Corrections(unittest.TestCase):
    def test_correction_adds_columns_and_keeps_raw(self):
        res = run([("SYN-a", synthetic_doc(ambientHumidity=130.0))])
        c1 = make_correction("SYN-a", 1, {"dht_humidity_pct": 13.0}, "decimal slip", "SYN-tester", SCHEMA)
        c2 = make_correction("SYN-a", 2, {"dht_humidity_pct": 83.0}, "re-read logger", "SYN-tester", SCHEMA)
        r = apply_corrections(res.records, [c2, c1], SCHEMA)[0]
        self.assertEqual(r["dht_humidity_pct"], 130.0)
        self.assertEqual(r["dht_humidity_pct__corrected"], 83.0)
        self.assertEqual(r["correction_version"], 2)
        self.assertEqual(c2["correctionId"], "SYN-a__v2")
        self.assertEqual(c2["source"], "manual")

    def test_rejects_uncorrectable_field_and_missing_reason(self):
        with self.assertRaises(ValueError):
            make_correction("SYN-a", 1, {"quality": "ok"}, "x", "y", SCHEMA)
        with self.assertRaises(ValueError):
            make_correction("SYN-a", 1, {"dht_temp_c": 30.0}, "", "y", SCHEMA)


if __name__ == "__main__":
    unittest.main()
