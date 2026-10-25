# PRISM decision support: setup and operations guide

PRISM's ML layer is **advisory decision support, not veterinary diagnosis**. It never controls
the sprinkler. Pump thresholds, schedules, manual ON/OFF and the ESP32 safety logic are untouched.

```
Collect (ESP32 -> Firestore) -> Validate + Export (pipeline/) -> Experiment (forecast/run.py)
  -> Train + Evaluate gate (forecast/retrain.py) -> Approve (admin) -> Activate (admin)
  -> Monitor (/ready, jobs, assessment_results) -> Rollback if needed
```

| Component | Code | Kind |
|---|---|---|
| B1 THI band | `prism-ml2.0/assess/thi_band.py` | rule |
| B2 forecast | `prism-ml2.0/forecast/` | ML, only once an approved model exists |
| A1 growth trend | `prism-ml2.0/assess/growth.py` | rule; manual weigh-ins only |
| A2 pen thermal flag | `prism-ml2.0/assess/pen_thermal.py` | statistical; pen-level |

## 1. Setup

```sh
cd prism-ml2.0
python -m venv venv && venv/Scripts/activate     # Windows; use venv/bin/activate on Linux/macOS
pip install -r requirements.txt                  # API (includes firebase_admin for token checks)
pip install -r requirements-data.txt             # export/corrections tools (adds nothing extra today)
pip install pyarrow                              # optional, only for --format parquet
uvicorn app.main:app --reload                    # local API
```

- The Flutter app needs `flutter pub get`.
- The rules tests need the Firebase CLI and Java.
- `.python-version` says 3.12. The local venv used for these tests is 3.13.1.

## 2. Environment variables

| Variable | Used by | Notes |
|---|---|---|
| `PRISM_FIREBASE_PROJECT` | API (`app/auth.py`) | e.g. `prism-3cd2c`. Needed to verify Firebase ID tokens. Without it, protected routes return 503 (fail closed). |
| `GOOGLE_APPLICATION_CREDENTIALS` | `pipeline/export.py --firestore`, `pipeline/corrections.py`, `app/admin_claims.py` | Path to a service-account JSON **kept outside the repository**. The API itself does not need it. |
| `PRISM_API_KEY` | legacy `/predict/*` | Optional shared key, unchanged from before. |
| `PORT` | `Procfile` | Set by the host. |
| `FIRESTORE_EMULATOR_HOST` | `tests_firestore_rules/run.mjs` | Defaults to `127.0.0.1:8089`. |

Never put keys in the app or the repository. The app holds no secrets and can run no privileged action.

## 3. Configuration (set these before looking at results)

| File | Holds | Still to fill |
|---|---|---|
| `config/assessment.json` | THI formula and bands, growth rules, A2 statistics | THI formula is a **placeholder**; THI thresholds and all growth values are `null` |
| `config/labels.json` | all wording | review |
| `config/validation.json` | data-quality limits | review project-defined values |
| `config/forecast.json` | horizons, features, splits, grids, seed, **`acceptance_rule`**, retrain schedule | `acceptance_rule` is `null`: no model can pass until the team sets it |
| `config/api.json` | limits, freshness, registry, lock, exports folder | review |
| `assets/config/assessment_ui.json` (app) | app wording, refresh interval | review |

## 4. API reference (`prism-ml2.0/app/`)

| Method & path | Access | Purpose |
|---|---|---|
| `GET /health` | public | liveness |
| `GET /ready` | public | 503 if auth is not configured; `degraded` if the active model failed to load |
| `POST /predict/farm`, `POST /predict/pig-growth` | `x-api-key` | old models; deprecated |
| `POST /api/farm/analyze`, `POST /api/pig/analyze` | signed-in user | calls the existing app already makes |
| `POST /assess/environment` | signed-in user | THI band, plus forecast if an approved model is active |
| `POST /assess/pig-growth` | signed-in user | A1 |
| `POST /assess/pen-thermal` | signed-in user | A2 |
| `GET /config/rules` | signed-in user | rule config for the app's offline fallback |
| `GET /models`, `GET /models/active`, `GET /models/{v}/evaluation` | admin | model info |
| `POST /models/{v}/approve` | admin | eligible → approved |
| `POST /models/{v}/activate`, `POST /models/rollback` | admin | switch the active model (atomic) |
| `POST /admin/retrain` `{"dataset_version"}` | admin | start a training job: 202 started, 200 duplicate, 404 no export, 409 lock busy |
| `GET /admin/jobs`, `GET /admin/jobs/{id}` | admin | job records |

**Error codes:**

| Code | Meaning |
|---|---|
| 401 | no or invalid token |
| 403 | not admin |
| 413 | body too large |
| 422 | invalid input |
| 409 | refused action or busy lock |
| 503 | auth not configured |

**Admin role:** a Firebase custom claim, granted with
`GOOGLE_APPLICATION_CREDENTIALS=... python -m app.admin_claims grant <uid>`.
The Firestore `admins` collection holds every user, so it is not a role.

## 5. Export real data (Phase 1)

```sh
python -m pipeline.export --firestore --start 2026-10-01 --end 2026-11-01 --out exports
python -m pipeline.export --firestore --full-scan --out exports    # also docs with string/1970 timestamps
```

- **Output:** `exports/<dataset_version>/`, containing `readings.csv`, `offline_periods.csv`,
  `raw_snapshot.jsonl` and `manifest.json`.
- **Flags only:** nothing is removed. Corrections are separate records:
  `python -m pipeline.corrections ...`.

## 6. Run the forecasting experiment (Phase 3)

```sh
python -m forecast.run --dataset exports/<dataset_version>
python -m forecast.run --pipeline-test       # synthetic; labelled "PIPELINE TEST ONLY, NOT VALID RESULTS"
```

- The run stops when there are too few independent days.
- The report is written to `reports/forecast/<dataset_version>/report.{json,md}`.

## 7. Retrain, approve, activate, roll back

1. **Train and evaluate** (never deploys). Pick one:
   - API: `POST /admin/retrain {"dataset_version": "<v>"}`
   - CLI: `python -m forecast.retrain run --dataset exports/<v>`
   - Schedule: only if you set one up. An external scheduler runs
     `python -m forecast.retrain run --latest`. Nothing runs per reading.

   What the job does:
   - Runs the Phase-3 experiment unchanged.
   - Refits the validation-chosen candidate and registers it as **candidate**.
   - Applies the gate. The candidate becomes **eligible** only if the acceptance rule passes
     against the baselines **and** against the current production model on the same held-out test
     rows. Otherwise it is **rejected**, and the reason is stored.

   Every run writes `models/registry/jobs/<job_id>/job.json`. It holds the job ID, times, dataset
   version, record and independent-day counts, feature schema, config and seed, metrics, previous
   and candidate versions, status, and any rejection reason or error. A repeat request with the
   same dataset and config returns the earlier result.
2. **Review and approve:** `POST /models/<v>/approve`, or `python -m forecast.retrain approve <v> --by <name>`.
3. **Activate:** `POST /models/<v>/activate`.
   - The model is loaded first, then the pointer is replaced atomically, then the in-memory swap
     happens.
   - Requests in flight keep using the old model until the swap.
4. **Roll back:** `POST /models/rollback` re-activates the previous version, which is kept in
   `ACTIVE.json`.
   - Activation and rollback go through the **running API**, because it holds the model in memory.
   - If you change `ACTIVE.json` by hand, restart the API.

Only one training, approval, activation or rollback runs at a time (`models/registry/.job.lock`).
A lock older than `lock_stale_after_s` is treated as left by a crashed job and is broken.

## 8. Monitor

- **`/ready`:** auth status and model state (`active`, `none` or `load_failed`).
- **API logs:** method, path, status and timing. Tokens and headers are never logged.
- **`assessment_results`** in Firestore: every stored result carries its model version, method,
  inputs and a link to the raw data. Use it to compare forecasts with the readings that followed.
- **`GET /admin/jobs`:** training history and rejection reasons.
- **What to watch:**
  - forecast error drifting above the test MAE in the model's evaluation
  - many `stale` or `offline` statuses, which point to sensor or connectivity problems
  - repeated rejections, which mean more or better data is needed

## 9. Tests

```sh
cd prism-ml2.0 && python -m unittest discover -s tests -t .     # Python (synthetic fixtures)
python -m tests.smoke_test                                       # legacy models
flutter test                                                     # app widgets (from repo root)
sh tests_firestore_rules/test.sh                                 # rules on the local emulator
```

## 10. Limitations

- **The AMG8833 is pen-level.**
  - It is an 8×8 array with about ±2.5 °C error, and it cannot tell which pig it sees.
  - All thermal outputs are about the pen, never a pig, and never a core body temperature.
  - The legacy field name `pigBodyTemp` is kept for app compatibility only.
- **There is no per-pig temperature** in PRISM, and none can be entered. Growth uses manual weigh-ins only.
- **One DHT22 location.** Air temperature and humidity come from a single point and may not
  represent the whole pen. No outside weather is logged.
- **Small data.**
  - Forecast results need at least 31 independent days under the current settings.
  - Confidence intervals are wide with few days.
  - One farm and one pen means limited generalisation.
- **History gaps today.** Current firmware stores DHT22 air temperature and misting state only in
  the live document, so THI history and A2 cannot use stored history until the firmware v2
  proposal (`docs/FIRMWARE_PROPOSAL_sensor_v2.md`) is approved and deployed.
- **The production comparison is conservative.** The production model may have been trained on
  data that overlaps the new test period, which favours production.
- **Placeholders.** The THI formula is a placeholder, and the THI and growth thresholds are unset
  until the team supplies them.

## 11. Out of scope: a supervised pig-health classifier

No such model exists, and none should be built until reviewed labels exist. If one is added later:
- Labels must come from a documented protocol: who assessed the pigs, how, when, with what criteria,
  and how disagreements are resolved.
- They must be stored with `source: "manual"` and a reviewer ID.
- **Never train on PRISM's own predictions or flags.** The registry, gate and job records above
  can be reused as they are.
