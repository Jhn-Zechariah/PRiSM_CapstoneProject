"""Pydantic request/response schemas. Bounds come from config (no literals here)."""
from datetime import date as Date, datetime as DateTime
from typing import Annotated, Any, Literal, Optional

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field

from app.settings import api_config, impossible

L = api_config()["limits"]
T_LO, T_HI = impossible("dht_temp_c")
H_LO, H_HI = impossible("dht_humidity_pct")
A_LO, A_HI = impossible("amg_summary_c")
S_LO, S_HI = impossible("sprinkler_active_s")

Text = Annotated[str, Field(max_length=L["max_text_len"])]
Flags = Annotated[list[Text], Field(max_length=L["max_quality_flags"])]
TempC = Annotated[float, Field(ge=T_LO, le=T_HI)]
HumPct = Annotated[float, Field(ge=H_LO, le=H_HI)]
AmgC = Annotated[float, Field(ge=A_LO, le=A_HI)]


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")


# ------------------------------------------------------------------ requests
class EnvReading(Strict):
    timestamp: AwareDatetime
    dht_temp_c: Optional[TempC] = None
    dht_humidity_pct: Optional[HumPct] = None
    dht_temp_valid: Optional[bool] = None
    dht_humidity_valid: Optional[bool] = None
    sprinkler_on: Optional[bool] = Field(default=None, description="logged misting state (read-only input)")
    sprinkler_active_s: Optional[Annotated[float, Field(ge=S_LO, le=S_HI)]] = None
    quality_flags: Flags = []


class EnvironmentIn(Strict):
    pen_id: Optional[Text] = None
    category: Optional[Text] = None
    previous_band: Optional[Text] = None
    readings: Annotated[list[EnvReading], Field(min_length=1, max_length=L["max_readings"])]


class WeighIn(Strict):
    date: Date | AwareDatetime
    weight_kg: Annotated[float, Field(gt=0, le=L["max_weight_kg"])]
    source: Optional[Literal["manual", "sensor"]] = None
    notes: Optional[Text] = None
    id: Optional[Text] = None


class PigIn(Strict):
    pig_id: Optional[Text] = None
    birth_date: Date
    sex: Optional[Text] = None
    breed: Optional[Text] = None
    pen_id: Optional[Text] = None


class PigGrowthAssessIn(Strict):
    pig: PigIn
    weights: Annotated[list[WeighIn], Field(max_length=L["max_weighins"])]


class PenReading(Strict):
    timestamp: AwareDatetime
    amg_summary_c: Optional[AmgC] = None
    dht_temp_c: Optional[TempC] = None
    amg_summary_c__state: Optional[Literal["normal", "missing", "sensor_offline", "flagged"]] = None
    dht_temp_c__state: Optional[Literal["normal", "missing", "sensor_offline", "flagged"]] = None
    quality: Optional[Literal["ok", "warn", "bad"]] = None


class PenThermalIn(Strict):
    pen_id: Optional[Text] = None
    current: PenReading
    history: Annotated[list[PenReading], Field(max_length=L["max_pen_history"])] = []


# Existing Flutter payloads (lib/core/services/ml_service.dart); extra fields tolerated.
class FlutterFarmIn(BaseModel):
    temperature_c: TempC
    humidity_pct: HumPct
    weight_change_kg: Optional[float] = None
    feed_intake_kg: Optional[float] = None
    medicine_given: Optional[int] = None


class FlutterPigIn(BaseModel):
    pig_id: Text
    birth_date: Date
    current_weight: Annotated[float, Field(gt=0, le=L["max_weight_kg"])]
    birth_weight: Optional[Annotated[float, Field(gt=0, le=L["max_weight_kg"])]] = None


# ------------------------------------------------------------------ responses
DataQuality = Literal["ok", "warning", "stale", "offline", "invalid", "insufficient"]


class InputItem(BaseModel):
    name: str
    value: Any = None
    unit: Optional[str] = None
    source: Literal["sensor", "manual"]
    observed_at: Optional[str] = None


class Forecast(BaseModel):
    target: str
    horizon_minutes: int
    value: float
    projected_band: Optional[str] = None
    method: Literal["ML"] = "ML"
    model_version: str
    note: str


class AssessmentOut(BaseModel):
    output: dict
    method: Literal["rule", "statistical", "rule+ML"]
    reasons: list[str]
    inputs_summary: list[InputItem]
    data_quality_status: DataQuality
    data_quality_warnings: list[str]
    config_warnings: list[str]
    config_version: str
    model_version: Optional[str] = None
    forecast: Optional[Forecast] = None
    timestamp: DateTime
    reference_type: Optional[str] = None
    advisory: bool = True
    disclaimer: str


class FlutterFarmOut(BaseModel):
    condition: str
    insights: list[str]
    recommendations: list[str]
    assessment: AssessmentOut


class FlutterPigOut(BaseModel):
    classification: Optional[str] = None
    insight: str
    recommendation: Optional[str] = None


class RetrainIn(Strict):
    dataset_version: Annotated[str, Field(pattern=r"^[A-Za-z0-9._-]{1,100}$")]


class ApproveIn(Strict):
    note: Optional[Text] = None
