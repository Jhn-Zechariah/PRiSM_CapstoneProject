"""Export validated sensor observations to CSV or Parquet.

  # from a local JSONL dump (one {"id", "create_time", "data"} object per line)
  python -m pipeline.export --input dump.jsonl --out exports

  # straight from Firestore (needs requirements-data.txt and GOOGLE_APPLICATION_CREDENTIALS)
  python -m pipeline.export --firestore --start 2026-10-01 --end 2026-10-19 --out exports

Writes exports/<dataset_version>/ with:
  readings.<csv|parquet>   one row per raw document (nothing dropped), quality flags,
                           correction columns, dataset_version column
  offline_periods.csv      gaps long enough to count as the device being offline
  raw_snapshot.jsonl       the exact raw input, so the export can be rebuilt
  manifest.json            version, config hash, counts, time range, synthetic marker
The dataset version is a hash of the exported table and the configs, so the same input
and rules always give the same version and any change gives a new one.
"""
import argparse
import hashlib
import json
import subprocess
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

from pipeline.config import config_fingerprint, load_schema, load_validation
from pipeline.corrections import apply_corrections
from pipeline.normalize import normalize, parse_time
from pipeline.validate import validate

LEAD_COLUMNS = ["dataset_version", "record_id", "device_key", "pen_id", "source", "schema_version",
                "timestamp_utc", "timestamp_type", "ingest_time_utc", "effective_time_utc",
                "time_basis", "quality", "quality_flags", "duplicate_of", "prev_gap_s"]


def read_jsonl(path):
    with open(path, encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def _cell(v):
    if isinstance(v, datetime):
        return v.isoformat()
    if isinstance(v, list):
        return ";".join(v) if all(isinstance(x, str) for x in v) else json.dumps(v)
    return v


def build_table(raw_rows, corrections, schema, vcfg, now):
    recs = [normalize(r["id"], r.get("data"), schema, r.get("create_time")) for r in raw_rows]
    result = validate(recs, vcfg, schema, now=now)
    rows = apply_corrections(result.records, corrections, schema)
    df = pd.DataFrame([{k: _cell(v) for k, v in r.items()} for r in rows])
    if df.empty:
        df = pd.DataFrame(columns=LEAD_COLUMNS[1:])
    lead = [c for c in LEAD_COLUMNS if c in df.columns]
    df = df[lead + sorted(c for c in df.columns if c not in lead)]
    periods = pd.DataFrame([{k: _cell(v) for k, v in p.items()} for p in result.offline_periods],
                           columns=["device_key", "offline_from_utc", "offline_until_utc", "duration_s",
                                    "last_record_before", "first_record_after"])
    return df, periods, result


def dataset_version(df, schema, vcfg, synthetic):
    h = hashlib.sha256()
    h.update(df.to_csv(index=False).encode())
    h.update(config_fingerprint(schema, vcfg).encode())
    prefix = "SYNTHETIC-" if synthetic else ""
    return f"{prefix}prism-sensor-s{schema['schema_version']}-{h.hexdigest()[:12]}"


def _git_commit():
    try:
        return subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True,
                              timeout=5).stdout.strip() or None
    except (OSError, subprocess.SubprocessError):
        return None


def export(raw_rows, out_dir, corrections=(), fmt="csv", now=None, input_desc="", schema=None, vcfg=None):
    schema = schema or load_schema()
    vcfg = vcfg or load_validation()
    now = now or datetime.now(timezone.utc)
    df, periods, result = build_table(raw_rows, list(corrections), schema, vcfg, now)
    synthetic = bool(df["synthetic"].any()) if "synthetic" in df.columns else False
    version = dataset_version(df, schema, vcfg, synthetic)
    df.insert(0, "dataset_version", version)

    target = Path(out_dir) / version
    target.mkdir(parents=True, exist_ok=True)
    if fmt == "parquet":
        try:
            df.to_parquet(target / "readings.parquet", index=False)
        except ImportError as e:
            raise SystemExit("Parquet needs pyarrow (pip install pyarrow), or use --format csv") from e
    else:
        df.to_csv(target / "readings.csv", index=False)
    periods.to_csv(target / "offline_periods.csv", index=False)
    with open(target / "raw_snapshot.jsonl", "w", encoding="utf-8") as f:
        for r in raw_rows:
            f.write(json.dumps(r, sort_keys=True) + "\n")

    flag_kinds = Counter(fl.split(":", 1)[0] for r in result.records for fl in r["quality_flags"])
    times = [r["effective_time_utc"] for r in result.records if r["effective_time_utc"] is not None]
    manifest = {
        "dataset_version": version,
        "contains_synthetic": synthetic,
        "note": ("SYNTHETIC data: tests/fixtures only, never use for reported results."
                 if synthetic else "Raw sensor observations; validation flags only, nothing removed."),
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "validation_reference_now_utc": now.isoformat(),
        "input": input_desc,
        "schema_version": schema["schema_version"],
        "validation_config_version": vcfg["version"],
        "config_sha256": config_fingerprint(schema, vcfg),
        "git_commit": _git_commit(),
        "format": fmt,
        "record_count": len(df),
        "quality_counts": dict(Counter(r["quality"] for r in result.records)),
        "flag_counts": dict(sorted(flag_kinds.items())),
        "offline_period_count": len(periods),
        "corrections_applied": int((df.get("correction_version", pd.Series(dtype=int)) > 0).sum()),
        "effective_time_range_utc": [min(times).isoformat(), max(times).isoformat()] if times else None,
    }
    (target / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return target, manifest


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    src = p.add_mutually_exclusive_group(required=True)
    src.add_argument("--input", help="JSONL dump of raw documents")
    src.add_argument("--firestore", action="store_true", help="read from Firestore")
    p.add_argument("--start", help="ISO date/time, UTC (Firestore mode)")
    p.add_argument("--end", help="ISO date/time, UTC, exclusive (Firestore mode)")
    p.add_argument("--full-scan", action="store_true",
                   help="read the whole collection, including docs with string/1970 timestamps")
    p.add_argument("--corrections", help="JSONL of correction docs (file mode)")
    p.add_argument("--out", default="exports")
    p.add_argument("--format", choices=["csv", "parquet"], default="csv")
    p.add_argument("--now", help="reference UTC time for the future-timestamp check (reproducibility)")
    a = p.parse_args(argv)

    schema = load_schema()
    now = parse_time(a.now)[0] if a.now else None
    if a.firestore:
        from pipeline import firestore_io
        start = parse_time(a.start)[0] if a.start else None
        end = parse_time(a.end)[0] if a.end else None
        raw = list(firestore_io.fetch_readings(schema["collection"], start, end, a.full_scan))
        corrections = firestore_io.fetch_corrections(schema["corrections_collection"])
        desc = f"firestore:{schema['collection']} start={a.start} end={a.end} full_scan={a.full_scan}"
    else:
        raw = read_jsonl(a.input)
        corrections = read_jsonl(a.corrections) if a.corrections else []
        desc = f"file:{a.input}"
    target, manifest = export(raw, a.out, corrections, a.format, now, desc, schema)
    print(f"wrote {target}")
    print(json.dumps({k: manifest[k] for k in ("dataset_version", "record_count", "quality_counts",
                                               "offline_period_count", "contains_synthetic")}, indent=2))


if __name__ == "__main__":
    main()
