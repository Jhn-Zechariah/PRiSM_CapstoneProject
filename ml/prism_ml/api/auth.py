"""Authentication for the two client types.

* Mobile app users: Firebase Authentication ID token in ``Authorization: Bearer <token>``. The token
  signature, audience (project id), issuer, expiry and subject are verified server-side.
* ESP32 devices: per-device shared secret (provisioned out of band, stored only on the device and in the
  server's secret store). Each request carries::

      X-PRISM-Device:    <device id>
      X-PRISM-Timestamp: <unix seconds>
      X-PRISM-Nonce:     <random, >= 16 chars>
      X-PRISM-Signature: hex(HMAC-SHA256(secret, "<ts>\\n<nonce>\\n<METHOD>\\n<path>\\n<sha256(body) hex>"))

  Requests outside the allowed clock skew, with a reused nonce or a bad signature are rejected, which
  protects against forged and replayed submissions.
"""
from __future__ import annotations

import hashlib
import hmac
import logging
import time
from dataclasses import dataclass
from typing import Callable, Optional

from fastapi import HTTPException, Request

log = logging.getLogger("prism_ml.auth")


@dataclass(frozen=True)
class UserPrincipal:
    uid: str


@dataclass(frozen=True)
class DevicePrincipal:
    device_id: str
    farm_id: str


class TokenVerificationError(Exception):
    pass


class FirebaseTokenVerifier:
    """Verifies Firebase ID tokens against Google's public keys (no service account required)."""

    CERTS_URL = "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com"

    def __init__(self, project_id: str):
        if not project_id:
            raise ValueError("FIREBASE_PROJECT_ID is required to verify Firebase ID tokens")
        self.project_id = project_id
        import cachecontrol
        import requests
        from google.auth.transport import requests as g_requests  # imported lazily: network transport

        # Google's signing certificates are cached per their Cache-Control headers, so verification
        # does not need a network round trip on every request.
        self._request = g_requests.Request(session=cachecontrol.CacheControl(requests.Session()))

    def __call__(self, token: str) -> dict:
        from google.oauth2 import id_token

        try:
            claims = id_token.verify_token(token, self._request, audience=self.project_id, certs_url=self.CERTS_URL,
                                           clock_skew_in_seconds=10)
        except Exception as exc:  # noqa: BLE001 - google-auth raises several types
            raise TokenVerificationError(type(exc).__name__) from exc
        if claims.get("iss") != f"https://securetoken.google.com/{self.project_id}":
            raise TokenVerificationError("issuer")
        if not claims.get("sub") or len(claims["sub"]) > 128:
            raise TokenVerificationError("subject")
        if claims.get("auth_time", 0) > time.time() + 10:
            raise TokenVerificationError("auth_time")
        return claims


def client_key(request: Request) -> str:
    return request.client.host if request.client else "unknown"


def authenticate_user(request: Request, verifier: Optional[Callable[[str], dict]], monitor) -> UserPrincipal:
    client = client_key(request)
    if monitor.blocked(client):
        raise HTTPException(status_code=429, detail="too_many_failed_attempts")
    header = request.headers.get("authorization", "")
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not token or len(token) > 4096:
        monitor.record_failure(client, "user_missing_token")
        raise HTTPException(status_code=401, detail="authentication_required", headers={"WWW-Authenticate": "Bearer"})
    if verifier is None:
        log.error("User authentication is not configured (FIREBASE_PROJECT_ID missing)")
        raise HTTPException(status_code=503, detail="authentication_unavailable")
    try:
        claims = verifier(token)
    except TokenVerificationError:
        monitor.record_failure(client, "user_invalid_token")
        raise HTTPException(status_code=401, detail="invalid_token", headers={"WWW-Authenticate": "Bearer"})
    return UserPrincipal(uid=claims["sub"])


def signing_string(ts: str, nonce: str, method: str, path: str, body: bytes) -> bytes:
    return f"{ts}\n{nonce}\n{method.upper()}\n{path}\n{hashlib.sha256(body).hexdigest()}".encode("utf-8")


def sign(secret: str, ts: str, nonce: str, method: str, path: str, body: bytes) -> str:
    return hmac.new(secret.encode("utf-8"), signing_string(ts, nonce, method, path, body), hashlib.sha256).hexdigest()


def authenticate_device(request: Request, body: bytes, device_secrets: dict, nonces, monitor,
                        max_skew_seconds: int, now: Optional[float] = None) -> DevicePrincipal:
    client = client_key(request)
    if monitor.blocked(client):
        raise HTTPException(status_code=429, detail="too_many_failed_attempts")
    h = request.headers
    device_id, ts, nonce, sig = (h.get("x-prism-device", ""), h.get("x-prism-timestamp", ""),
                                 h.get("x-prism-nonce", ""), h.get("x-prism-signature", ""))

    def fail(kind: str):
        monitor.record_failure(client, kind)
        raise HTTPException(status_code=401, detail="invalid_device_credentials")

    if not (device_id and ts.isdigit() and 16 <= len(nonce) <= 64 and len(sig) == 64):
        fail("device_missing_headers")
    entry = device_secrets.get(device_id)
    if entry is None:
        fail("device_unknown")
    now = time.time() if now is None else now
    if abs(now - int(ts)) > max_skew_seconds:
        fail("device_clock_skew")
    expected = sign(entry["secret"], ts, nonce, request.method, request.url.path, body)
    if not hmac.compare_digest(expected, sig.lower()):
        fail("device_bad_signature")
    if not nonces.add_if_new(f"{device_id}:{nonce}"):
        fail("device_replay")
    return DevicePrincipal(device_id=device_id, farm_id=entry["farm_id"])
