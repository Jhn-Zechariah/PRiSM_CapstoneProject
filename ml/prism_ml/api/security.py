"""Request-level security controls: body-size limit, rate limiting, auth-failure monitoring, replay cache.

The rate limiter and caches are in-memory and per process. Behind several instances, use a shared
store (e.g. Redis) or an API gateway limit as well (see docs/SECURITY.md).
"""
from __future__ import annotations

import hashlib
import logging
import threading
import time
from collections import defaultdict, deque

from starlette.types import ASGIApp, Message, Receive, Scope, Send

log = logging.getLogger("prism_ml.security")


def pseudonym(value: str) -> str:
    """Short, non-reversible identifier for logs (no raw user ids, device ids or IPs in logs)."""
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:12]


class SlidingWindowLimiter:
    def __init__(self, limit: int, window_seconds: float):
        self.limit, self.window = limit, window_seconds
        self._hits: dict[str, deque] = defaultdict(deque)
        self._lock = threading.Lock()

    def hit(self, key: str, now: float | None = None) -> bool:
        """Record a hit; return False if the key is over its limit."""
        now = time.monotonic() if now is None else now
        with self._lock:
            q = self._hits[key]
            while q and now - q[0] > self.window:
                q.popleft()
            if len(q) >= self.limit:
                return False
            q.append(now)
            return True

    def count(self, key: str, now: float | None = None) -> int:
        now = time.monotonic() if now is None else now
        with self._lock:
            q = self._hits[key]
            while q and now - q[0] > self.window:
                q.popleft()
            return len(q)


class AuthFailureMonitor:
    """Counts failed authentications per client and blocks clients that keep failing."""

    def __init__(self, limit: int, window_seconds: float):
        self.limit = limit
        self._failures = SlidingWindowLimiter(limit=10**9, window_seconds=window_seconds)

    def record_failure(self, client: str, kind: str) -> None:
        self._failures.hit(client)
        n = self._failures.count(client)
        if n >= self.limit:
            log.warning("auth_failures_threshold client=%s kind=%s failures=%d", pseudonym(client), kind, n)

    def blocked(self, client: str) -> bool:
        return self._failures.count(client) >= self.limit


class NonceCache:
    """Remembers device nonces for the signature validity window to reject replayed requests."""

    def __init__(self, ttl_seconds: float):
        self.ttl = ttl_seconds
        self._seen: dict[str, float] = {}
        self._lock = threading.Lock()

    def add_if_new(self, nonce: str, now: float | None = None) -> bool:
        now = time.monotonic() if now is None else now
        with self._lock:
            if len(self._seen) > 50_000:
                self._seen = {k: t for k, t in self._seen.items() if now - t <= self.ttl}
            t = self._seen.get(nonce)
            if t is not None and now - t <= self.ttl:
                return False
            self._seen[nonce] = now
            return True


class BodySizeLimitMiddleware:
    """Rejects request bodies larger than ``max_bytes`` (checks Content-Length and streamed size)."""

    def __init__(self, app: ASGIApp, max_bytes: int):
        self.app, self.max_bytes = app, max_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        headers = dict(scope.get("headers") or [])
        cl = headers.get(b"content-length")
        if cl is not None and (not cl.isdigit() or int(cl) > self.max_bytes):
            await _send_json(send, 413, b'{"error":"payload_too_large","message":"Request body is too large."}')
            return
        received = 0

        async def limited_receive() -> Message:
            nonlocal received
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > self.max_bytes:
                    raise _PayloadTooLarge()
            return message

        try:
            await self.app(scope, limited_receive, send)
        except _PayloadTooLarge:
            await _send_json(send, 413, b'{"error":"payload_too_large","message":"Request body is too large."}')


class _PayloadTooLarge(Exception):
    pass


class SecurityHeadersMiddleware:
    HEADERS = [
        (b"x-content-type-options", b"nosniff"),
        (b"cache-control", b"no-store"),
        (b"referrer-policy", b"no-referrer"),
        (b"x-frame-options", b"DENY"),
    ]

    def __init__(self, app: ASGIApp, hsts: bool):
        self.app = app
        self.extra = [(b"strict-transport-security", b"max-age=31536000; includeSubDomains")] if hsts else []

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        async def send_with_headers(message: Message) -> None:
            if message["type"] == "http.response.start":
                message.setdefault("headers", [])
                message["headers"] = list(message["headers"]) + self.HEADERS + self.extra
            await send(message)

        await self.app(scope, receive, send_with_headers)


async def _send_json(send: Send, status: int, body: bytes) -> None:
    await send({"type": "http.response.start", "status": status,
                "headers": [(b"content-type", b"application/json"), (b"content-length", str(len(body)).encode())]})
    await send({"type": "http.response.body", "body": body})
