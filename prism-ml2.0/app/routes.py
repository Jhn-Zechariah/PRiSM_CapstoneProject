"""New endpoints. Assessments need a signed-in user; model info and actions need admin.
No route here reads or writes sprinkler state or contacts the ESP32."""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import JSONResponse

from app.auth import admin_user, current_user
from app.registry import RegistryError
from app.schemas import (ApproveIn, AssessmentOut, EnvironmentIn, FlutterFarmIn, FlutterFarmOut, FlutterPigIn,
                         FlutterPigOut, PenThermalIn, PigGrowthAssessIn, RetrainIn)
from app import services

router = APIRouter()

META_PUBLIC_TO_ADMIN = ("version", "status", "target", "horizon_minutes", "dataset_version", "dataset_synthetic",
                        "features", "metrics", "trained_at", "candidate", "params", "acceptance")


def _now(request):
    return request.app.state.clock()


def _acfg(request):
    return request.app.state.acfg


# ------------------------------------------------------------------ readiness
@router.get("/ready")
def ready(request: Request):
    st = request.app.state
    _, _, version, error = st.models.snapshot()
    checks = {"config": "ok",
              "auth": "configured" if st.verifier is not None else "not_configured",
              "forecast_model": "active" if version else ("load_failed" if error else "none")}
    ok = st.verifier is not None
    body = {"ready": ok, "degraded": checks["forecast_model"] == "load_failed", "checks": checks}
    return JSONResponse(body, status_code=200 if ok else 503)


# ------------------------------------------------------------------ assessments (signed-in users)
@router.post("/assess/environment", response_model=AssessmentOut)
def assess_environment(body: EnvironmentIn, request: Request, user=Depends(current_user)):
    return services.environment(body, request.app.state.models, _acfg(request), _now(request))


@router.post("/assess/pig-growth", response_model=AssessmentOut)
def assess_pig_growth(body: PigGrowthAssessIn, request: Request, user=Depends(current_user)):
    return services.pig_growth(body, _acfg(request), _now(request))


@router.post("/assess/pen-thermal", response_model=AssessmentOut)
def assess_pen_thermal(body: PenThermalIn, request: Request, user=Depends(current_user)):
    return services.pen_thermal(body, _acfg(request), _now(request))


@router.get("/config/rules")
def rule_config(request: Request, user=Depends(current_user)):
    """Read-only rule settings so the app can compute the THI band itself when the API is
    unreachable. Contains no secrets and no model information."""
    acfg = _acfg(request)
    t = acfg["assessment"]["thi"]
    return {"config_version": acfg["version"],
            "thi": {"formula": t["formula"]["expression"], "formula_status": t["formula"].get("status"),
                    "band_keys": t["band_keys"], "default_category": t["default_category"],
                    "categories": t["categories"]},
            "impossible": {c: acfg["validation"]["channels"][c]["impossible"]
                           for c in ("dht_temp_c", "dht_humidity_pct")},
            "labels": {"status": acfg["labels"]["status"], "recommendations": acfg["labels"]["recommendations"],
                       "disclaimer": acfg["labels"]["disclaimer"]}}


# ------------------------------------------------------------------ existing Flutter calls
@router.post("/api/farm/analyze", response_model=FlutterFarmOut)
def flutter_farm(body: FlutterFarmIn, request: Request, user=Depends(current_user)):
    return services.flutter_farm(body, _acfg(request), _now(request))


@router.post("/api/pig/analyze", response_model=FlutterPigOut)
def flutter_pig(body: FlutterPigIn, request: Request, user=Depends(current_user)):
    return services.flutter_pig(body, _acfg(request))


# ------------------------------------------------------------------ model info + actions (admin)
def _registry_call(fn):
    try:
        return fn()
    except RegistryError as e:
        raise HTTPException(status_code=e.status, detail=str(e)) from None


def _meta_view(meta):
    return {k: meta.get(k) for k in META_PUBLIC_TO_ADMIN}


@router.get("/models")
def list_models(request: Request, admin=Depends(admin_user)):
    reg = request.app.state.models.registry
    pointer = reg.read_pointer()
    out = []
    for v in reg.versions():
        m = reg.metadata(v)
        out.append({"version": v, "status": m.get("status"), "dataset_version": m.get("dataset_version"),
                    "dataset_synthetic": m.get("dataset_synthetic"), "active": v == pointer.get("active"),
                    "servable": reg.servable_problem(m) is None})
    return {"models": out, "pointer": pointer}


@router.get("/models/active")
def active_model(request: Request, admin=Depends(admin_user)):
    _, meta, version, error = request.app.state.models.snapshot()
    return {"model_version": version, "load_error": error, "model": _meta_view(meta) if meta else None,
            "pointer": request.app.state.models.registry.read_pointer()}


@router.get("/models/{version}/evaluation")
def model_evaluation(version: str, request: Request, admin=Depends(admin_user)):
    meta = _registry_call(lambda: request.app.state.models.registry.metadata(version))
    return {"version": version, "status": meta.get("status"), "metrics": meta.get("metrics"),
            "evaluation": meta.get("evaluation"), "acceptance": meta.get("acceptance"),
            "dataset_version": meta.get("dataset_version"), "dataset_synthetic": meta.get("dataset_synthetic")}


@router.post("/models/{version}/activate")
def activate_model(version: str, request: Request, admin=Depends(admin_user)):
    pointer = _registry_call(lambda: request.app.state.models.activate(version, by=admin["uid"]))
    return {"activated": version, "pointer": pointer}


@router.post("/models/rollback")
def rollback_model(request: Request, admin=Depends(admin_user)):
    pointer = _registry_call(lambda: request.app.state.models.rollback(by=admin["uid"]))
    return {"activated": pointer["active"], "pointer": pointer}


@router.post("/models/{version}/approve")
def approve_model(version: str, request: Request, body: ApproveIn = ApproveIn(), admin=Depends(admin_user)):
    """eligible -> approved (human sign-off). Does not activate."""
    meta = _registry_call(lambda: request.app.state.models.approve(version, by=admin["uid"], note=body.note or ""))
    return {"version": version, "status": meta["status"], "history": meta.get("history", [])}


# ------------------------------------------------------------------ retraining (admin; never deploys)
@router.post("/admin/retrain", status_code=202)
def retrain(body: RetrainIn, request: Request, admin=Depends(admin_user)):
    from forecast import retrain as job       # heavy imports only when used
    reg = request.app.state.models.registry
    dataset_dir = request.app.state.exports_dir / body.dataset_version
    jid, existing = _registry_call(lambda: job.plan(reg, dataset_dir))
    if existing and existing.get("status") in job.FINAL:
        return JSONResponse({"job_id": jid, "status": existing["status"], "duplicate_request": True,
                             "candidate_version": existing.get("candidate_version")}, status_code=200)
    lock = _registry_call(lambda: reg.lock(f"retrain {jid} by {admin['uid']}").acquire())
    try:
        request.app.state.run_in_background(
            lambda: job.run_job(reg, dataset_dir, by=admin["uid"], trigger="admin_api", lock=lock))
    except Exception:
        lock.release()
        raise
    return {"job_id": jid, "status": "started"}


@router.get("/admin/jobs")
def list_jobs(request: Request, admin=Depends(admin_user)):
    keep = ("job_id", "status", "requested_at", "finished_at", "dataset_version", "candidate_version",
            "previous_version", "rejection_reason", "error")
    return {"jobs": [{k: j.get(k) for k in keep} for j in request.app.state.models.registry.jobs()]}


@router.get("/admin/jobs/{job_id}")
def get_job(job_id: str, request: Request, admin=Depends(admin_user)):
    rec = _registry_call(lambda: request.app.state.models.registry.job(job_id))
    rec.pop("config", None)                   # full config is in the job file; keep the reply small
    return rec


def utc_now():
    return datetime.now(timezone.utc)
