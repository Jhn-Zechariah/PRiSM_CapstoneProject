"""Minimal synchronous ASGI test client (stdlib + anyio, which FastAPI already installs).
Used because starlette's TestClient needs httpx/httpx2, which are not installed here."""
import json as _json

import anyio


class Response:
    def __init__(self, status, headers, body):
        self.status_code, self.headers, self.content = status, headers, body

    def json(self):
        return _json.loads(self.content)


def request(app, method, path, json=None, headers=None, raw=None, send_length=True):
    body = raw if raw is not None else (_json.dumps(json).encode() if json is not None else b"")
    hdrs = [(k.lower().encode(), v.encode()) for k, v in (headers or {}).items()]
    if body and not any(k == b"content-type" for k, _ in hdrs):
        hdrs.append((b"content-type", b"application/json"))
    if send_length:
        hdrs.append((b"content-length", str(len(body)).encode()))

    async def run():
        scope = {"type": "http", "asgi": {"version": "3.0"}, "http_version": "1.1", "method": method,
                 "scheme": "http", "path": path, "raw_path": path.encode(), "query_string": b"",
                 "root_path": "", "headers": hdrs, "client": ("testclient", 50000), "server": ("test", 80),
                 "state": {}}
        sent = {"done": False}
        out = {"status": None, "headers": {}, "body": b""}
        finished = anyio.Event()

        async def receive():
            if not sent["done"]:
                sent["done"] = True
                return {"type": "http.request", "body": body, "more_body": False}
            await finished.wait()
            return {"type": "http.disconnect"}

        async def send(msg):
            if msg["type"] == "http.response.start":
                out["status"] = msg["status"]
                out["headers"] = {k.decode(): v.decode() for k, v in msg.get("headers", [])}
            elif msg["type"] == "http.response.body":
                out["body"] += msg.get("body", b"")
                if not msg.get("more_body", False):
                    finished.set()

        await app(scope, receive, send)
        return Response(out["status"], out["headers"], out["body"])

    return anyio.run(run)
