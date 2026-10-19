"""Reproducible acquisition of the external candidate datasets listed in configs/datasets.json.

Files are written unchanged to ``data/raw/external/<key>/``. Each file is verified against the
repository-published MD5 (when one exists) and its SHA-256 is recorded in
``data/metadata/provenance.json`` together with the source URL, licence and retrieval time.
"""
from __future__ import annotations

import hashlib
import json
import shutil
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from prism_ml.config import METADATA_DIR, RAW_EXTERNAL_DIR, load_config

USER_AGENT = "PRISM-capstone-dataset-acquisition/1.0 (research use)"


class ChecksumError(RuntimeError):
    pass


def _hashes(path: Path) -> tuple[str, str]:
    md5, sha = hashlib.md5(), hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            md5.update(chunk)
            sha.update(chunk)
    return md5.hexdigest(), sha.hexdigest()


def _download(url: str, dest: Path, timeout: int = 600) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp, dest.open("wb") as out:  # noqa: S310 - fixed https URLs
        shutil.copyfileobj(resp, out, length=1 << 20)


def acquire(keys: Optional[list[str]] = None, from_dir: Optional[Path] = None, raw_dir: Path = RAW_EXTERNAL_DIR,
            metadata_dir: Path = METADATA_DIR) -> list[dict]:
    """Download (or copy from ``from_dir/<key>/``) and verify every registered file."""
    registry = load_config("datasets")["datasets"]
    records = []
    for ds in registry:
        if keys and ds["key"] not in keys:
            continue
        target = raw_dir / ds["key"]
        target.mkdir(parents=True, exist_ok=True)
        for f in ds["files"]:
            if not f["url"].startswith("https://"):
                raise ValueError(f"Refusing non-HTTPS source {f['url']}")
            dest = target / f["name"]
            tmp = dest.with_suffix(dest.suffix + ".part")
            if from_dir:
                shutil.copyfile(Path(from_dir) / ds["key"] / f["name"], tmp)
                how = f"copied from a local download of {f['url']}"
            else:
                _download(f["url"], tmp)
                how = "downloaded"
            md5, sha = _hashes(tmp)
            if f.get("md5") and md5 != f["md5"]:
                tmp.unlink()
                raise ChecksumError(f"{ds['key']}/{f['name']}: MD5 {md5} != published {f['md5']}")
            if f.get("size") and tmp.stat().st_size != f["size"]:
                tmp.unlink()
                raise ChecksumError(f"{ds['key']}/{f['name']}: size mismatch")
            tmp.replace(dest)
            records.append({"dataset": ds["key"], "doi": ds["doi"], "license": ds["license"], "file": f["name"],
                            "original_name": f.get("original_name", f["name"]), "source_url": f["url"],
                            "md5": md5, "md5_verified_against_publisher": bool(f.get("md5")), "sha256": sha,
                            "bytes": dest.stat().st_size, "acquired_via": how,
                            "acquired_at": datetime.now(timezone.utc).isoformat(timespec="seconds")})
    metadata_dir.mkdir(parents=True, exist_ok=True)
    prov_path = metadata_dir / "provenance.json"
    existing = json.loads(prov_path.read_text(encoding="utf-8")) if prov_path.exists() else []
    prov_path.write_text(json.dumps(existing + records, indent=2), encoding="utf-8")
    return records
