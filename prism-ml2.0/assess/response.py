"""The common response schema shared by every assessment component.

{
  "component":  "thi_band" | "growth_trend" | "pen_thermal",
  "status":     machine key (band key or status key),
  "status_label": wording from labels.json,
  "method":     "rule" | "statistical",
  "reasons":    [plain-language strings explaining the status],
  "inputs":     [{"name", "value", "unit", "source": "sensor"|"manual", "observed_at"}],
  "data_quality_warnings": [...],
  "config_warnings": [...]      e.g. placeholder formula, values pending review,
  "config_version": "assessment-x/labels-y+hash",
  "timestamp":  UTC ISO time the assessment was made,
  "reference_type": "context_only" when a benchmark is shown, else null,
  "details":    component-specific numbers,
  "advisory": true, "disclaimer": wording from labels.json
}
"""
from datetime import datetime, timezone

METHODS = ("rule", "statistical")
SOURCES = ("sensor", "manual")


def inp(name, value, source, unit=None, observed_at=None):
    if source not in SOURCES:
        raise ValueError(f"source must be one of {SOURCES}")
    if isinstance(observed_at, datetime):
        observed_at = observed_at.isoformat()
    return {"name": name, "value": value, "unit": unit, "source": source, "observed_at": observed_at}


def make_response(component, status, method, cfg, reasons=(), inputs=(), warnings=(),
                  config_warnings=(), details=None, reference_type=None, now=None):
    if method not in METHODS:
        raise ValueError(f"method must be one of {METHODS}")
    now = now or datetime.now(timezone.utc)
    labels = cfg["labels"]
    return {
        "component": component,
        "status": status,
        "status_label": labels["status"].get(status, status),
        "method": method,
        "reasons": list(reasons),
        "inputs": list(inputs),
        "data_quality_warnings": list(warnings),
        "config_warnings": list(config_warnings),
        "config_version": cfg["version"],
        "timestamp": now.isoformat(),
        "reference_type": reference_type,
        "details": details or {},
        "advisory": True,
        "disclaimer": labels["disclaimer"],
    }
