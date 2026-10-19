"""Versioned model registry with integrity checks, approval and rollback.

Layout (under ``PRISM_ARTIFACTS_DIR``, default ``ml/artifacts``)::

    registry.json                       # which model is approved + history
    models/<model_id>/model.joblib      # fitted estimator (joblib/pickle: TRUSTED FILES ONLY)
    models/<model_id>/metadata.json     # feature contract, classes, ranges, abstention, data provenance
    models/<model_id>/evaluation.json   # held-out metrics and acceptance result

Security: joblib uses pickle, which executes code on load. Models are therefore only ever loaded from
this directory, only if listed in ``registry.json`` and only if their SHA-256 matches the value
recorded when the model was registered. Uploaded or user-supplied files are never deserialised.
"""
from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

import joblib

from prism_ml.config import artifacts_dir

MODEL_ID_RE = re.compile(r"^[a-z0-9][a-z0-9_.-]{2,80}$")


class RegistryError(RuntimeError):
    pass


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


@dataclass
class LoadedModel:
    model_id: str
    estimator: Any
    metadata: dict
    evaluation: dict


class ModelRegistry:
    def __init__(self, root: Optional[Path] = None, testing_allow_fixture_models: bool = False):
        """``testing_allow_fixture_models`` exists only so the automated tests can exercise approval and
        rollback inside a temporary directory. It is never set by the API or the CLI scripts."""
        self.testing_allow_fixture_models = testing_allow_fixture_models
        self.root = Path(root) if root else artifacts_dir()
        self.models_dir = self.root / "models"
        self.registry_path = self.root / "registry.json"

    # ----------------------------------------------------------------------------------------------
    def _read(self) -> dict:
        if not self.registry_path.exists():
            return {"approved": None, "models": {}, "history": []}
        return json.loads(self.registry_path.read_text(encoding="utf-8"))

    def _write(self, reg: dict) -> None:
        self.root.mkdir(parents=True, exist_ok=True)
        tmp = self.registry_path.with_suffix(".tmp")
        tmp.write_text(json.dumps(reg, indent=2), encoding="utf-8")
        tmp.replace(self.registry_path)

    def _model_dir(self, model_id: str) -> Path:
        if not MODEL_ID_RE.match(model_id):
            raise RegistryError(f"Invalid model id: {model_id!r}")
        d = (self.models_dir / model_id).resolve()
        if self.models_dir.resolve() not in d.parents:
            raise RegistryError("Model path escapes the artifacts directory")
        return d

    # ----------------------------------------------------------------------------------------------
    def register(self, model_id: str, estimator: Any, metadata: dict, evaluation: dict) -> Path:
        d = self._model_dir(model_id)
        if d.exists():
            raise RegistryError(f"Model {model_id} already exists; model versions are immutable")
        d.mkdir(parents=True)
        model_path = d / "model.joblib"
        joblib.dump(estimator, model_path)
        (d / "metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
        (d / "evaluation.json").write_text(json.dumps(evaluation, indent=2), encoding="utf-8")
        reg = self._read()
        reg["models"][model_id] = {
            "status": "candidate",
            "registered_at": _now(),
            "sha256": {name: _sha256(d / name) for name in ("model.joblib", "metadata.json", "evaluation.json")},
            "acceptance_passed": bool(evaluation.get("acceptance", {}).get("passed")),
        }
        self._write(reg)
        return d

    def list_models(self) -> dict:
        return self._read()

    def approve(self, model_id: str, approved_by: str, note: str = "") -> None:
        reg = self._read()
        entry = reg["models"].get(model_id)
        if entry is None:
            raise RegistryError(f"Unknown model {model_id}")
        if not entry.get("acceptance_passed"):
            raise RegistryError(f"Model {model_id} did not pass the acceptance criteria and cannot be approved")
        if not approved_by.strip():
            raise RegistryError("approved_by is required")
        d = self._verify(model_id, entry)
        metadata = json.loads((d / "metadata.json").read_text(encoding="utf-8"))
        if (metadata.get("training_data", {}).get("contains_synthetic_fixtures", True)
                and not self.testing_allow_fixture_models):
            raise RegistryError(f"Model {model_id} was trained on synthetic test fixtures (or lacks provenance) "
                                "and can never be approved")
        previous = reg.get("approved")
        if previous and previous in reg["models"]:
            reg["models"][previous]["status"] = "retired"
        entry["status"] = "approved"
        reg["approved"] = model_id
        reg["history"].append({"action": "approve", "model_id": model_id, "previous": previous,
                               "by": approved_by, "note": note, "at": _now()})
        self._write(reg)

    def rollback(self, performed_by: str, note: str = "") -> Optional[str]:
        """Re-approve the model that was approved before the current one."""
        reg = self._read()
        current = reg.get("approved")
        previous = next((h["previous"] for h in reversed(reg["history"])
                         if h["action"] == "approve" and h["model_id"] == current), None)
        if current:
            reg["models"][current]["status"] = "rolled_back"
        if previous:
            self._verify(previous, reg["models"][previous])
            reg["models"][previous]["status"] = "approved"
        reg["approved"] = previous
        reg["history"].append({"action": "rollback", "model_id": previous, "previous": current,
                               "by": performed_by, "note": note, "at": _now()})
        self._write(reg)
        return previous

    def _verify(self, model_id: str, entry: dict) -> Path:
        d = self._model_dir(model_id)
        for name, expected in entry["sha256"].items():
            p = d / name
            if not p.exists() or _sha256(p) != expected:
                raise RegistryError(f"Integrity check failed for {model_id}/{name}")
        return d

    def load_approved(self) -> Optional[LoadedModel]:
        reg = self._read()
        model_id = reg.get("approved")
        if not model_id:
            return None
        d = self._verify(model_id, reg["models"][model_id])
        metadata = json.loads((d / "metadata.json").read_text(encoding="utf-8"))
        if (metadata.get("training_data", {}).get("contains_synthetic_fixtures", True)
                and not self.testing_allow_fixture_models):
            raise RegistryError(f"Refusing to serve {model_id}: trained on synthetic fixtures or missing provenance")
        estimator = joblib.load(d / "model.joblib")
        evaluation = json.loads((d / "evaluation.json").read_text(encoding="utf-8"))
        return LoadedModel(model_id, estimator, metadata, evaluation)
