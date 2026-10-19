# Implementation report: 2026-10-12

## Summary

* The paper, repository, firmware copy and earlier ML attempts were audited first (AUDIT_REPORT.md).
* Genuine external datasets were acquired with verified checksums and audited from the raw files.
  **None can train or validate a classifier on PRISM's sensors.** Together with the calibration phase
  (no clean Firestore data), this means **no classifier is trained or deployed**. A classifier was not
  manufactured to satisfy the interface.
* What was built and tested: a complete, leakage-resistant pipeline that trains only on blinded,
  reviewer-confirmed farm labels; pre-registered acceptance criteria; an integrity-checked model
  registry with approval and rollback; a data-quality layer that stops missing, stale or faulty data from
  ever producing "Good"; referenced sentence guidance; a secured FastAPI service; app integration with
  no placeholder inputs; and Firestore rules tested in the emulator.

## Completion status

| Requirement | Status |
|---|---|
| Inspect project before changes | Done (AUDIT_REPORT.md) |
| Investigate external datasets, verify provenance | Done: HotPig and INRAE downloaded, checksummed, audited; 3 others screened |
| Datasets used documented with real files/columns/units | Done. **Used for training: none** (reasons documented) |
| Synthetic data not misrepresented | Done: `prism-ml2.0` retired to `legacy/`; fixtures confined to tests and refused by loader and registry |
| Genuine fitted model from defensible data | **Blocked**: no labelled farm data. Pipeline ready and tested |
| Current status, not forecasts | Done (no temporal look-ahead features or outputs) |
| Labelling and validation strategy for the 3 classes | Done (protocol PRISM-LABEL-1.0, **draft, needs expert sign-off**) |
| Sentence-based, referenced, safety-conscious insights | Done |
| Invalid/stale/insufficient data cannot yield Good | Done and tested |
| Same feature contract in training and inference | Done (single function plus hash check) |
| FastAPI / Firebase / ESP32 / Flutter integration | API and Flutter done; Firestore rules written and tested but **not deployed**; **firmware not changed** (not in repo; deployed version unknown) |
| Auth, authorization, secrets, validation | Implemented and tested in software; deployment controls documented |
| Held-out evaluation results | **Blocked** (no data). Evaluation code tested on fixtures only |
| Automated tests run and recorded | Done (TESTING_AND_VALIDATION.md) |
| Retraining and model versioning procedure | Done |
| Required documentation | Done (A–K plus audit) |

## Files

**Created:**
`ml/` (whole project: `configs/*.json`, `prism_ml/**`, `scripts/{acquire_external,audit_external,export_readings,farms,train,registry}.py`, `scripts/make_local_tls.sh`,
`tests/**`, `templates/*.csv`, `data/metadata/{provenance,external_audit}.json`, `reports/external_dataset_audit.md`,
`requirements*.txt`, `requirements.lock.txt`, `.env.example`, `.gitignore`, `pyproject.toml`, `README.md`),
`firestore.rules`, `firestore-rules-tests/{package.json,package-lock.json,firebase.json,rules.test.mjs,.gitignore}`,
`test/ml_service_test.dart`, `legacy/README.md`, `docs/*.md`.

**Modified:**
* `lib/core/services/ml_service.dart`: rewritten for API v1 (`assess`, `requestFromSensorData`,
  `AssessmentResult`, `MlUnavailable`). Build-time base URL, https required in release, no placeholders,
  `ambientTemp` no longer used as air temperature, `analyzePig` fails fast.
* `lib/features/dashboard/presentation/pages/Dashboard_Screen.dart`: the recommendation card UI is
  unchanged. It now sends the live reading (AMG8833 frame + DHT22 air temperature and humidity) for the
  **overall farm status**, with no placeholder values. Recommendations appear only for a model-based
  status; otherwise the card shows "Unavailable" with "Recommendations unavailable at this moment. Model
  is not yet trained using real farm data." (or the sensor/data problem). Quick Stats no longer shows
  "Pig Status" (removed at the team's request); it gained one line,
  "Room Temp: <value> (Low/Normal/High)", for the DHT22 air temperature (grower comfort zone 15.6–23.9 °C).
* `lib/features/monitoring/presentation/pages/temperaturemonitoring.dart` and `humiditymonitoring.dart`:
  the Insights sections were **removed** (the farm-level recommendation lives on the Dashboard only).
  Original UI and colours kept. Low/Normal/High now use sourced bands: AMG8833 skin 32–35 °C (previously
  the rectal 38.7–39.8 °C range) and humidity 50–70 % (previously an unsourced 60–70 %). See
  docs/SENSOR_THRESHOLDS.md and `lib/core/constants/thermal_thresholds.dart`.
* `lib/features/pig_management/presentation/components/pig_profile_card.dart`: truthful "not available" message.
* `lib/core/services/farm_data_service.dart`: removed `getFarmMLInputs()` (fabricated 28 °C / 75 % fallbacks; unused).
* `functions/index.js`: `onLiveSensorUpdate` reads `pigBodyTemp`/`ambientHumidity` (falls back to the old
  names), respects validity flags, and describes the reading as a surface reading.
* `README.md`: replaced the Flutter boilerplate.

**Moved/retired:** `prism-ml2.0/` → `legacy/prism-ml2.0-synthetic/` (unchanged; `Procfile` →
`Procfile.disabled`). It contains the synthetic datasets, rule-labelled models and smoke test. Nothing
was deleted.

## Datasets and model

* HotPig (doi:10.5281/zenodo.17090997, CC-BY-4.0) and INRAE core body temperature
  (doi:10.57745/GPW3E1, Etalab 2.0): **excluded**. HotPig has no thermal or environmental values; INRAE
  has core temperature, setpoint-only ambient (22/24/32 °C) and no humidity or thermal array.
* Final model: **none approved**. Candidates: Decision Tree (baseline, per the paper), Random Forest,
  HistGradientBoosting. **Held-out results: none.** No genuine labelled data exist, so none are reported.

## Running the system

See README.md, ml/README.md and DEPLOYMENT.md. Key commands:
`python ml/scripts/acquire_external.py`, `python ml/scripts/audit_external.py`, `python ml/scripts/train.py`,
`uvicorn prism_ml.api.asgi:app` (in `ml/`, with `FIREBASE_PROJECT_ID`), `pytest` (in `ml/`),
`flutter test test/ml_service_test.dart`, `npm test` (in `firestore-rules-tests/`).

## Unresolved / blocked

1. **Labelled farm data** (blocks the model): finish calibration, update firmware, run blinded label sessions.
2. **Firmware** (not in repo; deployed version unknown): add `airTemp`/`airTempValid`, fix `waterValid`,
   device identity and TLS validation, and optionally HMAC ingestion.
3. **Rules deployment** depends on the firmware device identity; `.firebaserc` points to the wrong project.
4. Release keystore; API-key restrictions; multi-farm schema; multi-instance rate limiting.
5. Hardware end-to-end test and on-device UI test not performed.
6. Acceptance criteria and labelling protocol need adviser and expert sign-off.
7. `test/widget_test.dart` (pre-existing, commented out) still fails to load.

## Free-only and data-provenance audit (added for the free-only / zero-synthetic requirements)

Details and official references: [COST_AND_DEPENDENCIES.md](COST_AND_DEPENDENCIES.md).

1. **Services and libraries:** all libraries are open source (MIT/BSD/Apache-2.0) and installed locally.
   External services: Firebase Auth, Firestore and FCM (Spark, no payment method), public dataset
   repositories (no account). **No paid service, paid AI/LLM API, paid hosting, paid certificate or paid
   dataset was introduced.**
2. **Self-hosted by default:** the API, inference, insights, training, model registry and reading
   history (`sqlite` backend, added) run on the team's own machine. TLS uses the project's own CA
   (`scripts/make_local_tls.sh`) pinned in the app (verified live).
3. **Billing risks found in the existing architecture (not introduced by this work):**
   * `functions/` (Cloud Functions) **requires the Blaze plan**, which needs a billing account. If it is
     deployed today, billing is already attached to the project. Free alternatives are documented;
     changing the architecture needs your decision.
   * At the current 10-second push and 4-second poll rates, Firestore's Spark limits (20K writes/day,
     50K reads/day) can be exhausted. On Spark this causes an outage, not charges. Mitigations are documented;
     reading history now goes to self-hosted SQLite.
4. **Datasets for training/validation/testing:** none. HotPig, INRAE and the figshare fuzzy-logic study were
   verified and excluded (no compatible raw observations with defensible labels).
5. **Confirmation:** no synthetic data were used to train, validate or test any PRISM model, and no model
   has been trained. Synthetic records exist only as clearly tagged software-test fixtures, which the
   loader refuses by default and from which no model can be approved or served.
6. **Initial external-data training stage: BLOCKED.** The requested lifecycle starts with "genuine published
   research data → initial model". After verification, no accessible published dataset contains raw
   observations of PRISM's inputs (air temperature + RH + infrared/thermal-array surface temperature) with
   labels that can define Good / Needs Attention / High Risk without inventing cut-offs:
   * INRAE: core temperature with setpoint-only ambient (22/24/32 °C), no humidity or surface temperature.
   * HotPig: behaviour only.
   * Fuzzy-logic study (air temp + IR surface temp, the closest match): summary tables only.
   Options, none taken without your approval: **(a)** request raw data from the fuzzy-logic study's authors
   (doi:10.1590/1809-4430-eng.agric.v38n4p457-470/2018) or from IR-thermography heat-stress studies (free,
   but labels would still need a documented protocol); **(b)** skip the external stage and train the first
   model on reviewer-labelled farm data (the pipeline is ready); **(c)** use INRAE only for a different,
   documented task (e.g. describing core-temperature response), which cannot feed the app's classifier.
7. **Retraining with local data:** calibrate → firmware sends contract-v1 fields → signed ingestion into
   SQLite → `export_readings.py` → blinded reviewer label sessions (PRISM-LABEL-1.0) → `train.py` (grouped
   temporal hold-out, pre-registered acceptance) → `registry.py compare` → manual `approve` → `rollback` if
   needed. Model predictions are never used as labels; there is no automatic retraining.

### Decisions recorded (2026-10-12)

* **Initial model: option (b)** (chosen by the team). The first model is trained only on reviewer-labelled
  PRISM farm data collected with PRISM-LABEL-1.0 after calibration. External datasets stay excluded from
  training. The pipeline needed no change: it already trains only on trusted local labels.
* **Deployed firmware received** (`prismoct12`). The app now maps `ambientTemp` (DHT22) to `air_temp_c`
  (`ml_service.dart`), with a new contract test using the firmware's exact `/sensor` JSON layout
  (`ml/tests/contract/firmware_sensor_example.json`). Remaining firmware items: DEPLOYMENT.md §5,
  SECURITY.md open issues 1–2.

### Files added for these requirements

`ml/prism_ml/api/repository.py` (`SQLiteRepository`), `ml/scripts/{farms.py,export_readings.py,make_local_tls.sh}`
(`export_firestore.py` was replaced by `export_readings.py`), `ml/tests/test_sqlite_store.py`,
`lib/core/services/ml_http_client_{io,stub}.dart`, `test/ml_http_client_test.dart`,
`docs/COST_AND_DEPENDENCIES.md`. Modified: `ml_service.dart` (CA pinning), `auth.py` (certificate cache),
`settings.py`, `main.py`, `.env.example`, `requirements*.txt`, and the deployment, security, datasets and
retraining docs.
