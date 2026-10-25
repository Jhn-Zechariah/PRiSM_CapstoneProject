"""FastAPI service.  Local run:  uvicorn app.main:app --reload

Existing endpoints (/health, /predict/farm, /predict/pig-growth) are unchanged.
New endpoints live in app/routes.py. The active forecast model is loaded once at
startup and again only on activation (app/registry.py).
"""
import logging
import os
from logging.handlers import RotatingFileHandler
import threading
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

from app import predictor
from app.auth import build_verifier
from app.limits import BodyLimitAndLog
from app.registry import ModelState, Registry
from app.routes import router, utc_now
from app.settings import api_config, exports_path, registry_path
from assess import config as assess_config

_FMT = "%(asctime)s %(name)s %(levelname)s %(message)s"
logging.basicConfig(level=logging.INFO, format=_FMT)
# Also keep a small rotating log file (no tokens or headers are ever logged). PRISM_LOG_FILE="" disables it.
_log_file = os.environ.get("PRISM_LOG_FILE", str(Path(__file__).resolve().parent.parent / "logs" / "api.log"))
if _log_file:
    Path(_log_file).parent.mkdir(parents=True, exist_ok=True)
    _fh = RotatingFileHandler(_log_file, maxBytes=1_000_000, backupCount=3, encoding="utf-8")
    _fh.setFormatter(logging.Formatter(_FMT))
    logging.getLogger("prism").addHandler(_fh)

API_KEY = os.environ.get("PRISM_API_KEY")        # unset = no key required (local testing)


def check_key(x_api_key: str = Header(default=None)):
    if API_KEY and x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Unauthorized")


class FarmIn(BaseModel):
    body_temp: float = Field(ge=25, le=45, description="Body surface temperature (deg C)")
    ambient_temp: float = Field(ge=5, le=55, description="Ambient temperature (deg C)")
    humidity: float = Field(ge=0, le=100, description="Relative humidity (%)")


class PigGrowthIn(BaseModel):
    age_days: int = Field(ge=0, le=400)
    current_weight_kg: float = Field(gt=0, le=400)
    previous_weight_kg: float = Field(gt=0, le=400)
    days_between: int = Field(ge=1, le=120, description="Days between the two weigh-ins")


def init_state(app, verifier=..., registry_root=None, registry_cfg=None, clock=utc_now,
               exports_dir=None, run_in_background=None):
    """Builds app.state once. Tests pass a fake verifier, a temp registry, a fixed clock,
    a temp exports folder and a synchronous job runner."""
    if verifier is ...:
        verifier, _ = build_verifier()
    app.state.verifier = verifier
    app.state.acfg = assess_config.load()
    app.state.clock = clock
    reg = Registry(registry_root or registry_path(), registry_cfg or api_config()["registry"])
    app.state.models = ModelState(reg)
    app.state.models.load_active()
    app.state.exports_dir = Path(exports_dir) if exports_dir else exports_path()
    app.state.run_in_background = run_in_background or _thread
    return app


def _thread(fn):
    threading.Thread(target=fn, name="prism-retrain", daemon=True).start()


@asynccontextmanager
async def lifespan(app):
    if not hasattr(app.state, "models"):
        init_state(app)
    yield


def create_app():
    application = FastAPI(title="PRISM ML API", version="1.1.0", lifespan=lifespan)

    @application.get("/health")
    def health():
        return {"status": "ok"}

    @application.post("/predict/farm", dependencies=[Depends(check_key)], deprecated=True)
    def predict_farm(d: FarmIn):
        return predictor.predict_farm(d.body_temp, d.ambient_temp, d.humidity)

    @application.post("/predict/pig-growth", dependencies=[Depends(check_key)], deprecated=True)
    def predict_pig_growth(d: PigGrowthIn):
        return predictor.predict_pig_growth(d.age_days, d.current_weight_kg,
                                            d.previous_weight_kg, d.days_between)

    application.include_router(router)
    application.add_middleware(BodyLimitAndLog, max_bytes=api_config()["limits"]["max_request_bytes"])
    return application


app = create_app()
