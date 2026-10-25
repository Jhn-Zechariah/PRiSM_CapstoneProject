"""On-disk model registry and the in-memory active model.

models/registry/
  <version>/model.joblib       fitted sklearn Pipeline (forecast/register.py writes it)
  <version>/metadata.json      feature schema, dataset version, training config, metrics, status
  ACTIVE.json                  {"active", "previous", "updated_at", "updated_by"}

  jobs/<job_id>/job.json       one record per training run (forecast/retrain.py)
  .job.lock                    present while a training/approval/activation/rollback runs

Status lifecycle: candidate -> eligible | rejected (evaluation gate) -> approved (admin).
Only "approved" may be activated. ACTIVE.json and metadata are replaced atomically
(temp file in the same folder, then os.replace). Version folders are never deleted,
so the previous stable version stays available for rollback. A model must load before
the pointer moves. The model is loaded once at startup and again only on activation;
requests read the already-loaded object, so activation never interrupts inference.
"""
import json
import logging
import os
import re
import tempfile
import threading
from datetime import datetime, timezone
from pathlib import Path

import joblib

log = logging.getLogger("prism.api.registry")
VERSION_RE = re.compile(r"^[A-Za-z0-9._-]{1,100}$")


class RegistryError(Exception):
    """Raised for refused registry actions (bad version, not approved, load failure)."""
    def __init__(self, msg, status=409):
        super().__init__(msg)
        self.status = status


def atomic_write_json(path, data, prefix=".tmp-"):
    """Write to a temp file in the same folder, fsync, then os.replace (atomic)."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=prefix, suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, default=str)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise


class LockBusy(RegistryError):
    def __init__(self, holder):
        super().__init__(f"another training/approval/activation job is running ({holder})", 409)
        self.holder = holder


class JobLock:
    """One training / approval / activation / rollback at a time, across processes
    (API and CLI share the file). Non-blocking: a busy lock raises LockBusy.
    A lock older than lock_stale_after_s (crashed process) is broken and logged."""

    def __init__(self, path, owner, stale_after_s=None):
        self.path, self.owner, self.stale_after_s = Path(path), owner, stale_after_s
        self.held = False

    def acquire(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        for _ in range(2):
            try:
                fd = os.open(self.path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            except FileExistsError:
                try:
                    holder = json.loads(self.path.read_text(encoding="utf-8"))
                except (OSError, ValueError):
                    holder = {}
                age = datetime.now(timezone.utc).timestamp() - holder.get("since", 0)
                if self.stale_after_s and age > self.stale_after_s:
                    log.warning("breaking stale job lock held by %s (%.0f s old)", holder.get("owner"), age)
                    self.path.unlink(missing_ok=True)
                    continue
                raise LockBusy(holder.get("owner", "unknown")) from None
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump({"owner": self.owner, "since": datetime.now(timezone.utc).timestamp(),
                           "pid": os.getpid()}, f)
            self.held = True
            return self
        raise LockBusy("unknown")

    def release(self):
        if self.held:
            self.path.unlink(missing_ok=True)
            self.held = False

    def __enter__(self):
        return self.acquire()

    def __exit__(self, *exc):
        self.release()


class Registry:
    def __init__(self, root, cfg):
        self.root = Path(root)
        self.cfg = cfg
        self.pointer = self.root / cfg["pointer_file"]

    # ---------- reading
    def _dir(self, version):
        if not isinstance(version, str) or not VERSION_RE.match(version):
            raise RegistryError("invalid version id", 400)
        d = self.root / version
        if not (d / "metadata.json").is_file():
            raise RegistryError(f"unknown model version {version!r}", 404)
        return d

    def metadata(self, version):
        return json.loads((self._dir(version) / "metadata.json").read_text(encoding="utf-8"))

    def versions(self):
        if not self.root.is_dir():
            return []
        return sorted(p.name for p in self.root.iterdir() if (p / "metadata.json").is_file())

    def read_pointer(self):
        if not self.pointer.is_file():
            return {"active": None, "previous": None}
        return json.loads(self.pointer.read_text(encoding="utf-8"))

    def servable_problem(self, meta):
        if meta.get("status") != self.cfg["servable_status"]:
            return f"status is {meta.get('status')!r}, needs {self.cfg['servable_status']!r}"
        if meta.get("dataset_synthetic") and not self.cfg["allow_synthetic_models"]:
            return "model was trained on synthetic data"
        return None

    def load(self, version):
        """Returns (model, metadata) or raises RegistryError. Does not change the pointer."""
        meta = self.metadata(version)
        problem = self.servable_problem(meta)
        if problem:
            raise RegistryError(f"version {version} cannot be served: {problem}")
        try:
            model = joblib.load(self._dir(version) / "model.joblib")
        except Exception as e:
            raise RegistryError(f"version {version} failed to load ({type(e).__name__})") from None
        if not hasattr(model, "predict") or not meta.get("features"):
            raise RegistryError(f"version {version} is not a usable model (no predict() or feature list)")
        return model, meta

    # ---------- writing
    def _write_pointer(self, data):
        atomic_write_json(self.pointer, data, prefix=".ACTIVE-")

    def set_status(self, version, new, by, reason, allowed_from):
        """Status lifecycle: candidate -> eligible | rejected (evaluation gate, automatic)
        -> approved (admin). Every change is appended to metadata['history']."""
        meta = self.metadata(version)
        if meta.get("status") not in allowed_from:
            raise RegistryError(f"version {version} is {meta.get('status')!r}; "
                                f"{new!r} is only allowed from {list(allowed_from)}")
        meta.setdefault("history", []).append({"at": datetime.now(timezone.utc).isoformat(), "by": by,
                                               "from": meta.get("status"), "to": new, "reason": reason})
        meta["status"], meta["status_reason"] = new, reason
        atomic_write_json(self._dir(version) / "metadata.json", meta, prefix=".meta-")
        return meta

    # ---------- training job records
    @property
    def jobs_dir(self):
        return self.root / "jobs"

    def job(self, job_id):
        if not VERSION_RE.match(job_id or ""):
            raise RegistryError("invalid job id", 400)
        p = self.jobs_dir / job_id / "job.json"
        if not p.is_file():
            raise RegistryError(f"unknown job {job_id!r}", 404)
        return json.loads(p.read_text(encoding="utf-8"))

    def jobs(self):
        if not self.jobs_dir.is_dir():
            return []
        return sorted((json.loads((d / "job.json").read_text(encoding="utf-8"))
                       for d in self.jobs_dir.iterdir() if (d / "job.json").is_file()),
                      key=lambda j: j.get("requested_at") or "")

    def write_job(self, record):
        atomic_write_json(self.jobs_dir / record["job_id"] / "job.json", record, prefix=".job-")

    def lock(self, owner):
        return JobLock(self.root / ".job.lock", owner, self.cfg.get("lock_stale_after_s"))

    def set_active(self, version, by):
        cur = self.read_pointer()
        data = {"active": version,
                "previous": cur.get("active") if cur.get("active") != version else cur.get("previous"),
                "updated_at": datetime.now(timezone.utc).isoformat(), "updated_by": by}
        self._write_pointer(data)
        return data


class ModelState:
    """The loaded active model. Swapped under a lock; requests take a snapshot."""

    def __init__(self, registry):
        self.registry = registry
        self.lock = threading.Lock()
        self.model, self.meta, self.version, self.error = None, None, None, None

    def snapshot(self):
        with self.lock:
            return self.model, self.meta, self.version, self.error

    def load_active(self):
        version = self.registry.read_pointer().get("active")
        model = meta = error = None
        if version:
            try:
                model, meta = self.registry.load(version)
            except RegistryError as e:
                error = str(e)
                log.error("active model not loaded: %s", e)
        with self.lock:
            self.model, self.meta, self.version, self.error = model, meta, (version if model else None), error
        return self.snapshot()

    def activate(self, version, by):
        with self.registry.lock(f"activate {version} by {by}"):
            return self._activate(version, by)

    def _activate(self, version, by):
        # Load first; requests keep using the old model until the swap below.
        model, meta = self.registry.load(version)        # raises before anything changes
        try:
            pointer = self.registry.set_active(version, by)
        except OSError as e:                              # pointer untouched (atomic replace failed)
            raise RegistryError(f"could not update the active pointer ({type(e).__name__})", 500) from None
        with self.lock:
            self.model, self.meta, self.version, self.error = model, meta, version, None
        log.info("activated model %s (previous %s)", version, pointer["previous"])
        return pointer

    def rollback(self, by):
        with self.registry.lock(f"rollback by {by}"):
            prev = self.registry.read_pointer().get("previous")
            if not prev:
                raise RegistryError("no previous version to roll back to")
            return self._activate(prev, by)

    def approve(self, version, by, note=""):
        with self.registry.lock(f"approve {version} by {by}"):
            return self.registry.set_status(version, "approved", by, note or "approved by admin",
                                            allowed_from=("eligible",))
