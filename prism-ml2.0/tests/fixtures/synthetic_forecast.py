"""SYNTHETIC raw sensor documents for the forecasting PIPELINE TEST. NOT REAL DATA.

Every document has "_synthetic": true and SYN- ids, so the Phase-1 export marks the
dataset SYNTHETIC- and the experiment labels every output "pipeline test only".
Shape only: a daily temperature cycle, humidity moving opposite to it, a daily
misting period, rare sensor faults and one logging gap. The numbers mean nothing.
"""
import math
from datetime import datetime, timedelta, timezone

import numpy as np

TS = "__timestamp__"


def generate(days=40, pens=("SYN-pen1", "SYN-pen2"), step_min=5, seed=7,
             start=datetime(2026, 8, 1, tzinfo=timezone(timedelta(hours=8)))):
    rng = np.random.default_rng(seed)
    rows = []
    n = days * 1440 // step_min
    for p, pen in enumerate(pens):
        device = f"SYN-esp32-{p + 1}"
        day_offset = np.cumsum(rng.normal(0, 0.4, days))
        ar = 0.0
        mist_effect = 0.0
        for k in range(n):
            t_local = start + timedelta(minutes=k * step_min)
            d = k * step_min // 1440
            if p == 0 and d == 10 and 2 <= t_local.hour < 5:
                continue                                   # SYNTHETIC logging gap
            hour = t_local.hour + t_local.minute / 60
            mist_on = 12.0 <= hour < 12.25
            mist_effect = mist_effect * 0.8 + (1.0 if mist_on else 0.0)
            ar = 0.9 * ar + rng.normal(0, 0.15)
            temp = 27.5 + 0.5 * p + 3.5 * math.sin(2 * math.pi * (hour - 9) / 24) + day_offset[d] + ar \
                - 0.3 * mist_effect
            rh = float(np.clip(85 - 2.2 * (temp - 27.5) + rng.normal(0, 1.0), 40, 98.5))
            fault = rng.random() < 0.003
            t_utc = t_local.astimezone(timezone.utc)
            rows.append({
                "id": f"SYN-{device}-{int(t_utc.timestamp())}",
                "create_time": (t_utc + timedelta(seconds=1)).isoformat(),
                "data": {
                    "_synthetic": True, "schemaVersion": 2, "source": "sensor",
                    "deviceId": device, "penId": pen, "ntpSynced": True, "buffered": False,
                    "timestamp": {TS: t_utc.isoformat()},
                    "ambientTemp": round(temp, 1), "ambientTempValid": not fault,
                    "ambientHumidity": round(rh, 1), "ambientHumidityValid": True,
                    "pigBodyTemp": round(temp + 3 + rng.normal(0, 0.3), 2), "pigBodyTempValid": True,
                    "amgThermistor": round(temp + 1, 2), "waterPct": 60.0, "waterDistanceCm": 40.0,
                    "waterStatus": "Normal", "sprinkler": bool(mist_on),
                    "sprinklerActiveSec": int((hour - 12.0) * 3600) if mist_on else 0,
                    "wifiRssi": -60, "uptimeSec": k * step_min * 60}})
    return rows
