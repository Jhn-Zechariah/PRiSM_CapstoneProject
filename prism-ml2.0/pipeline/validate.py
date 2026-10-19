"""Flag-only validation of normalised sensor records.

Nothing is deleted or edited: every input record comes back (as a copy) with
  quality_flags  list of "<kind>[:<detail>]" strings, kinds listed in config/validation.json
  quality        "ok" | "warn" | "bad"   (worst severity; "info" flags do not lower quality)
  <channel>__state for each channel:
      normal          value present and passed every check
      missing         the field was not in the document (no data was sent)
      sensor_offline  firmware sent <x>Valid=false (sensor did not respond)
      flagged         value present but failed a check (impossible, out of range, stuck, ...)
A DEVICE offline period (no documents at all) shows up as a gap: the first record after it
gets "after_offline" and the period is listed in ValidationResult.offline_periods.
"""
from collections import namedtuple
from datetime import datetime, timedelta, timezone

ValidationResult = namedtuple("ValidationResult", ["records", "offline_periods"])

_RANK = {"info": 0, "warn": 1, "bad": 2}
UNKNOWN_DEVICE = "unknown-device"


def _severity(flag, vcfg):
    return vcfg["severity"].get(flag.split(":", 1)[0], "warn")


def _quality(flags, vcfg):
    worst = max((_RANK[_severity(f, vcfg)] for f in flags), default=0)
    return {0: "ok", 1: "warn", 2: "bad"}[worst]


def _outside(v, lo_hi):
    lo, hi = lo_hi
    return v < lo or v > hi


def _check_timestamp(r, flags, vcfg, schema, now):
    t = vcfg["timestamp"]
    ts, ingest = r["timestamp_utc"], r.get("ingest_time_utc")
    if ts is None:
        flags.append("missing_timestamp" if r["timestamp_type"] == "missing" else "missing_timestamp:unparseable")
        return None
    if r["timestamp_type"] != "firestore_timestamp":
        flags.append(f"timestamp_not_firestore_type:{r['timestamp_type']}")   # app queries won't see it
    min_valid = datetime.fromisoformat(t["min_valid_utc"].replace("Z", "+00:00"))
    future = timedelta(seconds=t["max_future_s"])
    if ts < min_valid or r.get("ntp_synced") is False:
        flags.append("stale_timestamp:ntp_unsynced")
        return None
    if now is not None and ts > now + future:
        flags.append("stale_timestamp:future")
        return None
    if ingest is not None and ts > ingest + future:
        flags.append("stale_timestamp:after_ingest")
        return None
    if ingest is not None and (ingest - ts).total_seconds() > t["max_ingest_lag_s"]:
        if r.get("buffered") is True:
            flags.append("late_arrival")          # replayed from the offline buffer: expected
            return ts
        flags.append("stale_timestamp:ingest_lag")
        return None
    return ts


def _expected_channels(r, schema):
    """v1 history docs are only known to carry the fields the app reads from history
    (status "existing"); live-doc-only and proposed fields being absent is not news."""
    if (r.get("schema_version") or 1) >= 2:
        return set(schema["channels"])
    return {c for c, s in schema["channels"].items() if s["status"] == "existing"}


def _check_channels(r, flags, vcfg, schema):
    expected = _expected_channels(r, schema)
    for ch, spec in schema["channels"].items():
        rules = vcfg["channels"].get(ch)
        state = "normal"
        if r.get(f"{ch}__valid") is False:
            flags.append(f"sensor_offline:{ch}")
            r[f"{ch}__state"] = "sensor_offline"
            continue
        if not r[f"{ch}__present"]:
            if ch in expected:
                flags.append(f"missing:{ch}")
            r[f"{ch}__state"] = "missing"
            continue
        v = r[ch]
        if v is None:                                    # present but wrong type
            flags.append(f"impossible:{ch}:type")
            r[f"{ch}__state"] = "flagged"
            continue
        if rules:
            if spec["type"] == "number_array":
                if len(v) != rules["length"] or any(x is None for x in v):
                    flags.append(f"invalid_frame:{ch}")
                    state = "flagged"
                elif any(_outside(x, rules["impossible"]) for x in v):
                    flags.append(f"impossible:{ch}")
                    state = "flagged"
                elif any(_outside(x, rules["plausible"]) for x in v):
                    flags.append(f"out_of_range:{ch}")
                    state = "flagged"
            else:
                if v in rules.get("sentinels", []):
                    flags.append(f"sentinel:{ch}")
                    state = "flagged"
                elif _outside(v, rules["impossible"]):
                    flags.append(f"impossible:{ch}")
                    state = "flagged"
                elif _outside(v, rules["plausible"]):
                    flags.append(f"out_of_range:{ch}")
                    state = "flagged"
        r[f"{ch}__state"] = state


def _usable(r, ch):
    return r[f"{ch}__state"] == "normal" or (
        r[f"{ch}__state"] == "flagged" and f"out_of_range:{ch}" in r["quality_flags"])


def _stuck_key(v, decimals):
    if isinstance(v, list):
        return tuple(round(x, decimals) for x in v)
    return round(v, decimals)


def _flag_stuck(seq, vcfg, schema):
    for ch in schema["channels"]:
        rules = vcfg["channels"].get(ch) or {}
        st = rules.get("stuck")
        if not st:
            continue
        run = []

        def close(run):
            if len(run) >= st["min_count"]:
                span = (run[-1]["effective_time_utc"] - run[0]["effective_time_utc"]).total_seconds()
                if span >= st["min_duration_s"]:
                    for x in run:
                        x["quality_flags"].append(f"stuck:{ch}")
                        if x[f"{ch}__state"] == "normal":
                            x[f"{ch}__state"] = "flagged"

        for r in seq:
            if not _usable(r, ch):
                close(run)
                run = []
                continue
            key = _stuck_key(r[ch], st["decimals"])
            if run and key != _stuck_key(run[-1][ch], st["decimals"]):
                close(run)
                run = []
            run.append(r)
        close(run)


def validate(records, vcfg, schema, now=None):
    """records: output of normalize(). now: reference time for the 'future' check
    (defaults to the current UTC time). Returns ValidationResult."""
    if now is None:
        now = datetime.now(timezone.utc)
    allowed_sources = schema["record_fields"]["source"]["allowed"]
    out = []
    for rec in records:
        r = dict(rec)
        flags = []
        r["quality_flags"] = flags
        trusted = _check_timestamp(r, flags, vcfg, schema, now)
        if r.get("source") not in allowed_sources:
            flags.append(f"unknown_source:{r.get('source')}")
        if trusted is not None:
            r["effective_time_utc"], r["time_basis"] = trusted, "device"
        elif r.get("ingest_time_utc") is not None:
            r["effective_time_utc"], r["time_basis"] = r["ingest_time_utc"], "ingest"
        else:
            r["effective_time_utc"], r["time_basis"] = None, "none"
        r["_trusted_ts"] = trusted
        _check_channels(r, flags, vcfg, schema)
        r["device_key"] = r.get("device_id") or UNKNOWN_DEVICE
        r["duplicate_of"] = ""
        r["prev_gap_s"] = None
        out.append(r)

    # ---- duplicates: earliest-ingested copy is the original, later copies are flagged ----
    far = datetime.max.replace(tzinfo=timezone.utc)
    by_id, by_time = {}, {}
    for r in sorted(out, key=lambda x: (x.get("ingest_time_utc") or far, x["record_id"])):
        if r["record_id"] in by_id:
            r["quality_flags"].append("duplicate:same_id")
            r["duplicate_of"] = r["record_id"]
            continue
        by_id[r["record_id"]] = r
        if r["_trusted_ts"] is not None:
            key = (r["device_key"], r["_trusted_ts"])
            if key in by_time:
                r["quality_flags"].append("duplicate:same_device_time")
                r["duplicate_of"] = by_time[key]["record_id"]
                continue
            by_time[key] = r

    # ---- gaps and stuck values, per device, in time order, duplicates excluded ----
    g = vcfg["gaps"]
    periods = []
    devices = {}
    for r in out:
        if r["effective_time_utc"] is not None and not r["duplicate_of"]:
            devices.setdefault(r["device_key"], []).append(r)
    for dev, seq in devices.items():
        seq.sort(key=lambda x: (x["effective_time_utc"], x["record_id"]))
        for prev, cur in zip(seq, seq[1:]):
            gap = (cur["effective_time_utc"] - prev["effective_time_utc"]).total_seconds()
            cur["prev_gap_s"] = gap
            if gap > g["offline_after_s"]:
                cur["quality_flags"].append("after_offline")
                periods.append({"device_key": dev,
                                "offline_from_utc": prev["effective_time_utc"],
                                "offline_until_utc": cur["effective_time_utc"],
                                "duration_s": gap,
                                "last_record_before": prev["record_id"],
                                "first_record_after": cur["record_id"]})
            elif gap > g["missed_readings_after_s"]:
                cur["quality_flags"].append("missed_readings")
        _flag_stuck(seq, vcfg, schema)

    for r in out:
        r.pop("_trusted_ts", None)
        r["quality"] = _quality(r["quality_flags"], vcfg)
    return ValidationResult(out, periods)
