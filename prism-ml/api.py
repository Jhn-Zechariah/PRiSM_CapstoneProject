"""PRISM forecasting API (FastAPI). Predictions are computed on request and never stored.

    uvicorn api:app --reload                      # local (needs credentials + PRISM_API_KEY)

Environment variables:
  PRISM_API_KEY              required; clients send it in the X-API-Key header
  FIREBASE_CREDENTIALS_JSON  service-account JSON text (Railway)   } one of
  GOOGLE_APPLICATION_CREDENTIALS  path to a key file (local)      } these
  PRISM_MODEL_PATH           optional, default models/current_model.joblib

Firestore reads are kept low: an in-memory 60-minute window is filled once, then
only documents newer than the last timestamp seen are fetched, and the answer is
cached for `cache_ttl_s` so many app requests share one refresh.
"""
from __future__ import annotations

import os
import secrets
import threading
import time
from datetime import datetime, timedelta, timezone
from typing import Callable, Literal

import pandas as pd
from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from common import AMB, CURRENT_MODEL_PATH, HUM, PIG, SPR, get_firestore_client, load_config
from features import build_features, compute_thi, max_lookback
import model_io
from preprocess import to_minute_frame
from risk import recommendation, risk_level
from sanity import check_live_window

SERVICE_VERSION = "2.0.0"

Status = Literal["ok", "insufficient_data", "stale_data", "out_of_training_range",
                 "model_unavailable", "firestore_error"]


class CurrentReading(BaseModel):
    pig_surface_temp_c: float | None
    ambient_temp_c: float | None
    humidity_pct: float | None
    thi: float | None
    sprinkler_on: bool


class PredictResponse(BaseModel):
    status: Status
    message: str
    latest_reading_at: datetime | None = None
    generated_at: datetime
    predicted_pig_temp_15min_c: float | None = None
    predicted_pig_temp_30min_c: float | None = None
    risk_level: Literal["Good", "Needs Attention", "High Risk"] | None = None
    recommendation: str | None = None
    current: CurrentReading | None = None
    model_version: str | None = None
    synthetic_only_model: bool | None = None
    cached: bool = False
    disclaimer: str


class HealthResponse(BaseModel):
    status: Literal["ok", "degraded"]
    service_version: str
    model_loaded: bool
    model_name: str | None = None
    model_version: str | None = None
    model_data_source: str | None = None
    synthetic_only_model: bool | None = None
    trained_at: str | None = None
    uptime_s: float


# ----------------------------------------------------------------------------- Firestore access
class FirestoreSource:
    """The only place that talks to Firestore. Every method is a bounded query."""

    def __init__(self, client, cfg: dict):
        self.client, self.fs = client, cfg["firestore"]

    def readings_after(self, after: datetime, limit: int) -> list[dict]:
        from google.cloud.firestore_v1.base_query import FieldFilter
        ts = self.fs["timestamp_field"]
        q = (self.client.collection(self.fs["readings_collection"])
             .where(filter=FieldFilter(ts, ">", after))
             .order_by(ts).limit(limit))
        return [d.to_dict() for d in q.stream()]

    def sprinkler_logs_after(self, after: datetime, limit: int = 50) -> list[dict]:
        from google.cloud.firestore_v1.base_query import FieldFilter
        ts = self.fs["timestamp_field"]
        q = (self.client.collection(self.fs["sprinkler_logs_collection"])
             .where(filter=FieldFilter(ts, ">", after))
             .order_by(ts).limit(limit))
        return [d.to_dict() for d in q.stream()]

    def live(self) -> dict | None:
        snap = self.client.collection(self.fs["live_collection"]).document(self.fs["live_document"]).get()
        return snap.to_dict() if snap.exists else None


def _utc(ts) -> datetime:
    return pd.Timestamp(ts).tz_convert("UTC").to_pydatetime() if pd.Timestamp(ts).tzinfo \
        else pd.Timestamp(ts).tz_localize("UTC").to_pydatetime()


class LiveWindow:
    """Rolling in-memory copy of the latest `window_min` minutes of readings."""

    def __init__(self, source: FirestoreSource, cfg: dict, clock: Callable[[], datetime]):
        self.source, self.cfg, self.clock = source, cfg, clock
        self.rows: list[dict] = []
        self.last_ts: datetime | None = None
        self.logs: list[dict] = []
        self.last_log_ts: datetime | None = None
        self.logs_fetched_at = -1e18
        self.live_on = False
        self.reads = 0   # documents read so far (for monitoring cost)

    def _fetch_readings(self, after: datetime):
        limit = self.cfg["api"]["max_docs_per_refresh"]
        while True:
            docs = self.source.readings_after(after, limit)
            self.reads += max(1, len(docs))
            for d in docs:
                if d.get("timestamp") is None:
                    continue
                d["timestamp"] = _utc(d["timestamp"])
                self.rows.append({"timestamp": d["timestamp"], PIG: d.get(PIG), AMB: d.get(AMB), HUM: d.get(HUM)})
            if docs:
                after = max(d["timestamp"] for d in docs if d.get("timestamp") is not None)
                self.last_ts = max(self.last_ts or after, after)
            if len(docs) < limit:
                break

    def refresh(self):
        api = self.cfg["api"]
        now = self.clock()
        window = timedelta(minutes=api["window_min"])
        if self.last_ts is None or now - self.last_ts > window:
            # cold start, or idle for longer than the window: re-seed instead of reading the whole gap
            self.rows, self.last_ts = [], None
            self._fetch_readings(now - window)
        else:
            self._fetch_readings(self.last_ts)
        if self.last_ts is not None:
            cutoff = self.last_ts - window
            self.rows = [r for r in self.rows if r["timestamp"] > cutoff]

        cap = timedelta(minutes=self.cfg["features"]["minutes_since_spray_cap"])
        if time.monotonic() - self.logs_fetched_at >= api["sprinkler_logs_refresh_s"]:
            after = self.last_log_ts or (now - cap - window)
            docs = self.source.sprinkler_logs_after(after)
            self.reads += max(1, len(docs))
            for d in docs:
                d["timestamp"] = _utc(d["timestamp"])
                self.logs.append({"timestamp": d["timestamp"], "durationSec": float(d.get("durationSec") or 0)})
                self.last_log_ts = max(self.last_log_ts or d["timestamp"], d["timestamp"])
            self.logs = [l for l in self.logs if l["timestamp"] > now - cap - window]
            self.logs_fetched_at = time.monotonic()

        live = self.source.live()
        self.reads += 1
        self.live_on = bool(live.get(SPR)) if live else False


def compute_prediction(rows: list[dict], logs: list[dict], live_on: bool, bundle: dict | None,
                       cfg: dict, now: datetime) -> dict:
    """Pure decision logic for /predict (no I/O), so it can be unit-tested."""
    api = cfg["api"]
    base = {"generated_at": now, "disclaimer": cfg["risk"]["disclaimer"]}
    if bundle is not None:
        base.update(model_version=bundle.get("version"), synthetic_only_model=bundle.get("synthetic_only"))
    if bundle is None:
        return {**base, "status": "model_unavailable", "message": "No trained model is loaded on the server."}
    if not rows:
        return {**base, "status": "insufficient_data", "message": "No sensor readings in the last hour."}

    raw = pd.DataFrame(rows)
    latest = _utc(raw["timestamp"].max())
    base["latest_reading_at"] = latest
    if now - latest > timedelta(minutes=api["stale_after_min"]):
        mins = int((now - latest).total_seconds() // 60)
        return {**base, "status": "stale_data",
                "message": f"No new sensor reading for {mins} minutes. Check the ESP32 and its WiFi."}

    start = pd.Timestamp(latest) - pd.Timedelta(minutes=api["window_min"])
    logs_df = pd.DataFrame(logs, columns=["timestamp", "durationSec"])
    frame = to_minute_frame(raw, cfg, logs=logs_df, live_on=live_on, source="real",
                            start=start, end=pd.Timestamp(latest))
    last = frame.iloc[-1]
    thi = compute_thi(last[AMB], last[HUM]) if pd.notna(last[AMB]) and pd.notna(last[HUM]) else None
    f = lambda v: None if pd.isna(v) else round(float(v), 2)
    base["current"] = CurrentReading(pig_surface_temp_c=f(last[PIG]), ambient_temp_c=f(last[AMB]),
                                     humidity_pct=f(last[HUM]), thi=f(thi) if thi is not None else None,
                                     sprinkler_on=bool(last[SPR]))

    rng = check_live_window(frame, cfg, env=bundle.get("envelope"))
    if rng["outside"]:
        return {**base, "status": "out_of_training_range",
                "message": ("Current readings are outside the range the model was trained on "
                            f"({', '.join(rng['variables'])}); a forecast would be unreliable.")}

    # last spray that ended before the window, so minutes-since-spray matches training
    last_spray = None
    if len(logs_df):
        ends = pd.to_datetime(logs_df["timestamp"], utc=True) + pd.to_timedelta(logs_df["durationSec"], unit="s")
        ends = ends[ends <= frame.index[0]]
        if len(ends):
            last_spray = ends.max().floor("min")
    X = build_features(frame, cfg, last_spray_before=last_spray).iloc[[-1]]
    if X[bundle["feature_columns"]].isna().any(axis=1).iloc[0]:
        have = int(frame[[PIG, AMB, HUM]].notna().all(axis=1).sum())
        return {**base, "status": "insufficient_data",
                "message": (f"Need at least {max_lookback(cfg) + 1} minutes of continuous readings; "
                            f"usable minutes in the last hour: {have}.")}

    preds = model_io.predict(bundle, X)
    p15, p30 = float(preds[15][0]), float(preds[30][0])
    level = risk_level(max(p15, p30), cfg)
    return {**base, "status": "ok", "message": "Forecast computed from the latest readings.",
            "predicted_pig_temp_15min_c": round(p15, 2), "predicted_pig_temp_30min_c": round(p30, 2),
            "risk_level": level, "recommendation": recommendation(level, bool(last[SPR]), cfg)}


# ----------------------------------------------------------------------------- app
def create_app(source: FirestoreSource | None = None, bundle: dict | None = None,
               clock: Callable[[], datetime] | None = None, cfg: dict | None = None,
               load_model: bool = True) -> FastAPI:
    cfg = cfg or load_config()
    clock = clock or (lambda: datetime.now(timezone.utc))
    app = FastAPI(title="PRISM forecast API", version=SERVICE_VERSION)
    state = {"bundle": bundle, "source": source, "window": None, "cache": None, "started": time.monotonic()}
    lock = threading.Lock()

    if state["bundle"] is None and load_model:
        try:
            state["bundle"] = model_io.load(os.environ.get("PRISM_MODEL_PATH", CURRENT_MODEL_PATH))
        except Exception as e:   # the service still answers /health
            print(f"[api] model not loaded: {type(e).__name__}")

    def require_key(x_api_key: str | None = Header(default=None)):
        expected = os.environ.get("PRISM_API_KEY")
        if not expected:
            raise HTTPException(503, "Server API key is not configured")
        if not x_api_key or not secrets.compare_digest(x_api_key, expected):
            raise HTTPException(401, "Invalid or missing X-API-Key")

    @app.get("/health", response_model=HealthResponse)
    def health():
        b = state["bundle"]
        return HealthResponse(
            status="ok" if b else "degraded", service_version=SERVICE_VERSION, model_loaded=b is not None,
            model_name=b and b.get("model_name"), model_version=b and b.get("version"),
            model_data_source=b and b.get("data_source"), synthetic_only_model=b and b.get("synthetic_only"),
            trained_at=b and b.get("trained_at"), uptime_s=round(time.monotonic() - state["started"], 1))

    @app.get("/predict", response_model=PredictResponse, dependencies=[Depends(require_key)])
    def predict():
        ttl = cfg["api"]["cache_ttl_s"]
        with lock:
            c = state["cache"]
            if c and time.monotonic() - c[0] < ttl:
                return {**c[1], "cached": True}
            if state["bundle"] is None:
                body = compute_prediction([], [], False, None, cfg, clock())
                return JSONResponse(PredictResponse(**body).model_dump(mode="json"), status_code=503)
            try:
                if state["window"] is None:
                    src = state["source"] or FirestoreSource(get_firestore_client(), cfg)
                    state["source"] = src
                    state["window"] = LiveWindow(src, cfg, clock)
                w = state["window"]
                w.refresh()
            except Exception as e:
                print(f"[api] firestore refresh failed: {type(e).__name__}")
                body = {"status": "firestore_error", "message": "Could not read sensor data from Firestore.",
                        "generated_at": clock(), "disclaimer": cfg["risk"]["disclaimer"]}
                return JSONResponse(PredictResponse(**body).model_dump(mode="json"), status_code=503)
            body = PredictResponse(**compute_prediction(w.rows, w.logs, w.live_on, state["bundle"],
                                                        cfg, clock())).model_dump()
            state["cache"] = (time.monotonic(), body)
            return body

    app.state.prism = state
    return app


app = create_app()
