"""ASGI middleware: request body size limit (413) and request logging without headers."""
import json
import logging
import time

log = logging.getLogger("prism.api.access")


async def _send_json(send, status, detail):
    body = json.dumps({"detail": detail}).encode()
    await send({"type": "http.response.start", "status": status,
                "headers": [(b"content-type", b"application/json"), (b"content-length", str(len(body)).encode())]})
    await send({"type": "http.response.body", "body": body})


class BodyLimitAndLog:
    def __init__(self, app, max_bytes):
        self.app, self.max_bytes = app, max_bytes

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        t0, status = time.perf_counter(), {"code": None}
        headers = dict(scope.get("headers") or [])
        cl = headers.get(b"content-length")
        try:
            if cl is not None and int(cl) > self.max_bytes:
                status["code"] = 413
                return await _send_json(send, 413, f"request body larger than {self.max_bytes} bytes")
        except ValueError:
            status["code"] = 400
            return await _send_json(send, 400, "invalid content-length")
        finally:
            if status["code"]:
                log.info("%s %s -> %s", scope["method"], scope["path"], status["code"])

        # Read the whole body (bounded) BEFORE the app sees it, so a body without
        # Content-Length cannot slip past the limit.
        chunks, size = [], 0
        while True:
            msg = await receive()
            if msg["type"] != "http.request":
                break
            size += len(msg.get("body", b""))
            if size > self.max_bytes:
                status["code"] = 413
                await _send_json(send, 413, f"request body larger than {self.max_bytes} bytes")
                log.info("%s %s -> 413", scope["method"], scope["path"])
                return
            chunks.append(msg.get("body", b""))
            if not msg.get("more_body", False):
                break
        body, replayed = b"".join(chunks), {"done": False}

        async def replay_receive():
            if not replayed["done"]:
                replayed["done"] = True
                return {"type": "http.request", "body": body, "more_body": False}
            return await receive()

        async def tracking_send(msg):
            if msg["type"] == "http.response.start":
                status["code"] = msg["status"]
            await send(msg)

        try:
            await self.app(scope, replay_receive, tracking_send)
        finally:
            # path only: query strings and headers (Authorization) are never logged
            log.info("%s %s -> %s (%.0f ms)", scope["method"], scope["path"], status["code"],
                     (time.perf_counter() - t0) * 1000)
