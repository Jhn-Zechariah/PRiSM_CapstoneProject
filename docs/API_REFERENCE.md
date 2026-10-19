# PRISM ML API reference (v1)

Base URL: configured per deployment (`https://<your-api-host>`). JSON only (`Content-Type:
application/json`); maximum request body 16 KB. All examples use placeholders.

## Authentication

| Client | Mechanism |
|---|---|
| Mobile app user | `Authorization: Bearer <Firebase ID token>`. Verified for signature, audience = `FIREBASE_PROJECT_ID`, issuer, expiry and subject. |
| ESP32 device | HMAC-SHA256 request signature with a per-device secret (below). |

Rate limits (per process): 30 requests/min per user, 20/min per device. After 10 failed authentications
in 5 minutes a client address receives `429` until the window passes.

## Common error format

```json
{"error": "invalid_token", "message": "Authentication is required or the credentials are invalid.", "request_id": "3f2a…"}
```

| HTTP | `error` values |
|---|---|
| 401 | `authentication_required`, `invalid_token`, `invalid_device_credentials` |
| 403 | `forbidden` (not a member of the farm / device path mismatch) |
| 404 | `no_readings`, path not found |
| 413 | `payload_too_large` |
| 415 | `unsupported_media_type` |
| 422 | `invalid_request` (+ `fields: [{loc, type}]`; input values are never echoed), `device_id_mismatch` |
| 429 | `rate_limited`, `too_many_failed_attempts` |
| 500 | `internal_error` (no details; search server logs by `request_id`) |
| 503 | `authentication_unavailable`, `storage_unavailable`, `stored_reading_invalid` |

## `GET /health`

No auth. `200 {"status": "ok"}`.

## `GET /v1/model` (user)

```json
{"available": false, "model": null, "reason": "no_approved_model", "feature_contract_version": "1.0.0"}
```
`reason`: `no_approved_model` | `model_load_failed` | null.

## `POST /v1/assessments` (user)

Assess one reading (the app sends its latest live reading).

Request (`schema_version` "1"; unknown fields are rejected):

| Field | Type / unit | Meaning |
|---|---|---|
| `observed_at` | ISO-8601 with timezone (UTC) | time the reading was taken (device NTP clock) |
| `air_temp_c`, `air_temp_valid` | °C, bool | DHT22 air temperature |
| `relative_humidity_pct`, `humidity_valid` | % RH, bool | DHT22 humidity |
| `thermal_pixels_c`, `thermal_valid` | 64 × °C (row-major 8×8), bool | AMG8833 frame (apparent surface temperature) |
| `water_level_pct`, `water_valid` | %, bool | HC-SR04 tank level (guidance only) |
| `calibration_profile` | string ≤ 64 | optional calibration id |
| `device_id` | string ≤ 64 | optional |

Missing values may be `null`; the data-quality layer reports them. Example:

```json
{"schema_version": "1", "observed_at": "2026-10-12T04:00:00Z",
 "air_temp_c": 30.1, "air_temp_valid": true, "relative_humidity_pct": 81.0, "humidity_valid": true,
 "thermal_pixels_c": [35.4, 35.6, "… 64 values …"], "thermal_valid": true,
 "water_level_pct": 55.0, "water_valid": true}
```

Response `200` (real response with no approved model; full example in
`ml/tests/contract/assessment_response_example.json`):

```json
{"api_version": "1", "status": "Classification Unavailable", "status_kind": "operational",
 "reason": "no_approved_model", "observed_at": "2026-10-12T04:00:00+00:00", "reading_age_seconds": 3.1,
 "measurements": {"air_temp_c": 30.1, "relative_humidity_pct": 81.0, "thermal_max_c": 35.6, "water_level_pct": 55.0},
 "data_quality": {"ok": true, "operational_status": null, "reading_age_seconds": 3.1, "issues": []},
 "model": null, "confidence": null, "probabilities": null, "details": {},
 "insights": [{"text": "No Good / Needs Attention / High Risk status is shown because …", "kind": "status", "references": []},
              {"text": "Latest readings: air temperature 30.1 °C, …", "kind": "observation", "references": ["ADAFRUIT_DHT", "ADAFRUIT_AMG8833"]}],
 "references": [{"id": "VERMEER2023", "citation": "Vermeer, H. M. & Aarnink, …", "url": "https://doi.org/10.5281/zenodo.7620726"}],
 "disclaimer": "PRISM is a monitoring aid. …", "feature_contract_version": "1.0.0"}
```

`status` values:

| `status` | `status_kind` | Meaning |
|---|---|---|
| Good / Needs Attention / High Risk | thermal | from the approved trained model; `confidence` and `probabilities` set |
| Insufficient Data | operational | missing, stale or unflagged readings |
| Sensor Check Required | operational | device-flagged invalid, out of range, flat frame, unsynced clock, calibration mismatch |
| Classification Unavailable | operational | no approved model, or model load/inference failure (`reason`) |
| Uncertain | operational | outside the validated range (`details.outside_features`) or confidence below the threshold |

`insights[].kind`: `status`, `observation`, `evidence`, `why`, `action`, `safety`, `data_quality`,
`reference_context`, `transparency`.

## `GET /v1/farms/{farm_id}/assessment/latest` (user, farm member)

Assesses the latest reading stored in `farms/{farm_id}/sensor_readings` (requires
`PRISM_STORAGE_BACKEND=firestore`). Non-members receive `403`; no stored readings gives `404`.
Response as above.

## `POST /v1/devices/{device_id}/readings` (device)

Body: the same reading schema. Headers:

```
X-PRISM-Device:    esp32-pen-1
X-PRISM-Timestamp: 1791705600            (unix seconds, within ±300 s of server time)
X-PRISM-Nonce:     <16–64 random chars, never reused>
X-PRISM-Signature: hex(HMAC_SHA256(secret, ts + "\n" + nonce + "\n" + "POST" + "\n" + path + "\n" + hex(SHA256(body))))
```

`path` is the URL path, e.g. `/v1/devices/esp32-pen-1/readings`. Response:
`{"accepted": true, "stored": true, "reading_id": "…", "data_quality": {…}}`. Readings that fail quality
checks are still stored, with `accepted: false` and the report, so faults are auditable.

## Mobile integration

`lib/core/services/ml_service.dart`: `MlService.assess(LiveSensorService.latestData.value)` builds the
request (`requestFromSensorData`) and parses `AssessmentResult`. Build with
`--dart-define=PRISM_API_BASE_URL=https://<your-api-host>`; release builds refuse non-https URLs.
Contract tests: `test/ml_service_test.dart` and `ml/tests/test_api.py::test_response_matches_mobile_contract`.
