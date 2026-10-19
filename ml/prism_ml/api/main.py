"""PRISM ML API (v1).

Application factory. The ASGI entry point is prism_ml.api.asgi:app.
Endpoints are documented in docs/API_REFERENCE.md.
"""
from __future__ import annotations

import json
import logging
import time
import uuid
from typing import Callable, Optional

from fastapi import Depends, FastAPI, HTTPException, Path, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import ValidationError

from prism_ml.api import auth
from prism_ml.api.repository import Repository, StorageUnavailable, make_repository
from prism_ml.api.schemas import ID_PATTERN, AssessmentOut, IngestOut, ModelInfoOut, ReadingIn
from prism_ml.api.security import (AuthFailureMonitor, BodySizeLimitMiddleware, NonceCache, SecurityHeadersMiddleware,
                                   SlidingWindowLimiter, pseudonym)
from prism_ml.api.settings import Settings, get_settings
from prism_ml.data.quality import check_reading
from prism_ml.features.contract import contract_version
from prism_ml.models.inference import Assessor

log = logging.getLogger("prism_ml.api")

ERROR_MESSAGES = {
    400: "The request could not be processed.",
    401: "Authentication is required or the credentials are invalid.",
    403: "You do not have access to this farm.",
    404: "Not found.",
    405: "Method not allowed.",
    413: "Request body is too large.",
    415: "Content type must be application/json.",
    422: "The request body is invalid.",
    429: "Too many requests. Please wait and try again.",
    503: "The service is temporarily unavailable.",
}


def create_app(settings: Optional[Settings] = None, assessor: Optional[Assessor] = None,
               verifier: Optional[Callable[[str], dict]] = None, repository: Optional[Repository] = None) -> FastAPI:
    settings = settings or get_settings()
    app = FastAPI(title="PRISM ML API", version="1.0.0",
                  docs_url="/docs" if settings.enable_docs else None, redoc_url=None,
                  openapi_url="/openapi.json" if settings.enable_docs else None)

    if verifier is None and settings.firebase_project_id:
        verifier = auth.FirebaseTokenVerifier(settings.firebase_project_id)
    state = app.state
    state.settings = settings
    state.assessor = assessor or Assessor()
    state.verifier = verifier
    state.repository = repository or make_repository(settings.storage_backend, settings.sqlite_path)
    state.user_limiter = SlidingWindowLimiter(settings.rate_limit_per_minute, 60)
    state.device_limiter = SlidingWindowLimiter(settings.device_rate_limit_per_minute, 60)
    state.auth_monitor = AuthFailureMonitor(settings.auth_fail_limit, settings.auth_fail_window_seconds)
    state.nonces = NonceCache(2 * settings.device_signature_max_skew_seconds)

    # ----- middleware (outermost last) ---------------------------------------------------------
    if settings.cors_origins:
        app.add_middleware(CORSMiddleware, allow_origins=list(settings.cors_origins), allow_methods=["GET", "POST"],
                           allow_headers=["Authorization", "Content-Type"], allow_credentials=False)
    app.add_middleware(BodySizeLimitMiddleware, max_bytes=settings.max_body_bytes)
    app.add_middleware(SecurityHeadersMiddleware, hsts=settings.is_production)

    @app.middleware("http")
    async def request_log(request: Request, call_next):
        rid = uuid.uuid4().hex[:16]
        request.state.request_id = rid
        t0 = time.perf_counter()
        response = await call_next(request)
        response.headers["X-Request-ID"] = rid
        log.info("request id=%s method=%s path=%s status=%s ms=%.1f", rid, request.method,
                 request.scope.get("route").path if request.scope.get("route") else "-",
                 response.status_code, (time.perf_counter() - t0) * 1000)
        return response

    # ----- error handling: never leak stack traces, secrets or input values --------------------
    def _err(request: Request, status: int, code: str, extra: Optional[dict] = None):
        body = {"error": code, "message": ERROR_MESSAGES.get(status, "Request failed."),
                "request_id": getattr(request.state, "request_id", None)}
        if extra:
            body.update(extra)
        return body

    @app.exception_handler(HTTPException)
    async def http_error(request: Request, exc: HTTPException):
        code = exc.detail if isinstance(exc.detail, str) else "error"
        return JSONResponse(_err(request, exc.status_code, code), status_code=exc.status_code,
                            headers=getattr(exc, "headers", None))

    @app.exception_handler(RequestValidationError)
    async def validation_error(request: Request, exc: RequestValidationError):
        fields = [{"loc": [str(p) for p in e.get("loc", [])], "type": e.get("type")} for e in exc.errors()]
        return JSONResponse(_err(request, 422, "invalid_request", {"fields": fields[:20]}), status_code=422)

    @app.exception_handler(Exception)
    async def unhandled(request: Request, exc: Exception):
        log.exception("unhandled_error id=%s", getattr(request.state, "request_id", None))
        return JSONResponse(_err(request, 500, "internal_error"), status_code=500)

    # ----- dependencies --------------------------------------------------------------------------
    def current_user(request: Request) -> auth.UserPrincipal:
        user = auth.authenticate_user(request, state.verifier, state.auth_monitor)
        if not state.user_limiter.hit(f"user:{user.uid}"):
            raise HTTPException(status_code=429, detail="rate_limited")
        return user

    def require_json(request: Request) -> None:
        ctype = request.headers.get("content-type", "")
        if not ctype.lower().startswith("application/json"):
            raise HTTPException(status_code=415, detail="unsupported_media_type")

    # ----- endpoints -----------------------------------------------------------------------------
    @app.get("/health")
    def health():
        return {"status": "ok"}

    @app.get("/v1/model", response_model=ModelInfoOut)
    def model_info(user: auth.UserPrincipal = Depends(current_user)):
        a = state.assessor
        reason = None if a.model else ("model_load_failed" if a.load_error else "no_approved_model")
        return ModelInfoOut(available=a.model is not None, model=a.model_info(), reason=reason,
                            feature_contract_version=contract_version())

    @app.post("/v1/assessments", response_model=AssessmentOut, dependencies=[Depends(require_json)])
    def assess(reading: ReadingIn, user: auth.UserPrincipal = Depends(current_user)):
        result = state.assessor.assess(reading.to_reading())
        log.info("assessment user=%s status=%s reason=%s", pseudonym(user.uid), result.status, result.reason)
        return result.as_dict()

    @app.get("/v1/farms/{farm_id}/assessment/latest", response_model=AssessmentOut)
    def latest_assessment(farm_id: str = Path(pattern=ID_PATTERN), user: auth.UserPrincipal = Depends(current_user)):
        try:
            if not state.repository.is_member(farm_id, user.uid):
                raise HTTPException(status_code=403, detail="forbidden")
            stored = state.repository.latest_reading(farm_id)
        except StorageUnavailable:
            raise HTTPException(status_code=503, detail="storage_unavailable")
        except HTTPException:
            raise
        except Exception:  # noqa: BLE001 - upstream (Firestore) failure or timeout
            log.exception("storage_error")
            raise HTTPException(status_code=503, detail="storage_unavailable")
        if stored is None:
            raise HTTPException(status_code=404, detail="no_readings")
        try:
            reading = ReadingIn(**stored)
        except ValidationError:
            raise HTTPException(status_code=503, detail="stored_reading_invalid")
        return state.assessor.assess(reading.to_reading()).as_dict()

    @app.post("/v1/devices/{device_id}/readings", response_model=IngestOut, dependencies=[Depends(require_json)])
    async def ingest(request: Request, device_id: str = Path(pattern=ID_PATTERN)):
        body = await request.body()
        device = auth.authenticate_device(request, body, settings.device_secrets, state.nonces, state.auth_monitor,
                                          settings.device_signature_max_skew_seconds)
        if device.device_id != device_id:
            state.auth_monitor.record_failure(auth.client_key(request), "device_path_mismatch")
            raise HTTPException(status_code=403, detail="forbidden")
        if not state.device_limiter.hit(f"device:{device.device_id}"):
            raise HTTPException(status_code=429, detail="rate_limited")
        try:
            payload = ReadingIn.model_validate(json.loads(body))
        except (ValueError, ValidationError):
            raise HTTPException(status_code=422, detail="invalid_request")
        if payload.device_id not in (None, device.device_id):
            raise HTTPException(status_code=422, detail="device_id_mismatch")
        reading = payload.to_reading()
        report = check_reading(reading)
        data = payload.model_dump()
        data["device_id"] = device.device_id
        try:
            rid = state.repository.store_reading(device.farm_id, device.device_id, data, report.as_dict())
            stored = True
        except StorageUnavailable:
            raise HTTPException(status_code=503, detail="storage_unavailable")
        except Exception:  # noqa: BLE001
            log.exception("storage_error")
            raise HTTPException(status_code=503, detail="storage_unavailable")
        return IngestOut(accepted=report.ok, stored=stored, reading_id=rid, data_quality=report.as_dict())

    return app

