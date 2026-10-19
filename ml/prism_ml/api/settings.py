"""Runtime configuration from environment variables (see ml/.env.example). No secrets have defaults."""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from functools import lru_cache


def _int(name: str, default: int) -> int:
    return int(os.environ.get(name, default))


@dataclass(frozen=True)
class Settings:
    env: str = "development"
    firebase_project_id: str = ""
    cors_origins: tuple[str, ...] = ()
    max_body_bytes: int = 16_384
    rate_limit_per_minute: int = 30
    device_rate_limit_per_minute: int = 20
    auth_fail_limit: int = 10
    auth_fail_window_seconds: int = 300
    device_signature_max_skew_seconds: int = 300
    device_secrets: dict = field(default_factory=dict)  # {device_id: {"secret": str, "farm_id": str}}
    storage_backend: str = "none"                       # "none" | "sqlite" | "firestore" | "memory"
    sqlite_path: str = ""
    enable_docs: bool = False

    @property
    def is_production(self) -> bool:
        return self.env == "production"


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    env = os.environ.get("PRISM_ENV", "development")
    raw_devices = os.environ.get("PRISM_DEVICE_SECRETS_JSON", "")
    devices = json.loads(raw_devices) if raw_devices else {}
    s = Settings(
        env=env,
        firebase_project_id=os.environ.get("FIREBASE_PROJECT_ID", ""),
        cors_origins=tuple(o.strip() for o in os.environ.get("PRISM_CORS_ORIGINS", "").split(",") if o.strip()),
        max_body_bytes=_int("PRISM_MAX_BODY_BYTES", 16_384),
        rate_limit_per_minute=_int("PRISM_RATE_LIMIT_PER_MINUTE", 30),
        device_rate_limit_per_minute=_int("PRISM_DEVICE_RATE_LIMIT_PER_MINUTE", 20),
        auth_fail_limit=_int("PRISM_AUTH_FAIL_LIMIT", 10),
        auth_fail_window_seconds=_int("PRISM_AUTH_FAIL_WINDOW_SECONDS", 300),
        device_signature_max_skew_seconds=_int("PRISM_DEVICE_MAX_SKEW_SECONDS", 300),
        device_secrets=devices,
        storage_backend=os.environ.get("PRISM_STORAGE_BACKEND", "none"),
        sqlite_path=os.environ.get("PRISM_SQLITE_PATH", ""),
        enable_docs=os.environ.get("PRISM_ENABLE_DOCS", "false").lower() == "true" and env != "production",
    )
    if s.is_production and not s.firebase_project_id:
        raise RuntimeError("FIREBASE_PROJECT_ID must be set in production")
    if "*" in s.cors_origins:
        raise RuntimeError("Wildcard CORS origins are not allowed")
    for dev_id, d in devices.items():
        if len(d.get("secret", "")) < 32 or not d.get("farm_id"):
            raise RuntimeError(f"Device {dev_id}: secret must be >= 32 characters and farm_id is required")
    return s
