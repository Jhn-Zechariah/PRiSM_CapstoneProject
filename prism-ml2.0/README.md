# PRISM ML

Two Decision Tree classifiers served by FastAPI.
See the deployment guide for the full step-by-step.

    python -m ml.make_datasets   # build synthetic training data
    python -m ml.train           # train + evaluate + save models/
    python -m tests.smoke_test   # sanity checks
    uvicorn app.main:app --reload

## Sensor data pipeline (independent of the API)

Validates and exports raw sensor observations. It only flags records and never deletes them.
Thresholds live in `config/validation.json`, field mappings in `config/sensor_schema.json`.

    python -m unittest discover -s tests -t .                       # tests (synthetic fixtures)
    python -m pipeline.export --input dump.jsonl --out exports      # export a JSONL dump
    pip install -r requirements-data.txt                            # for Firestore access
    python -m pipeline.export --firestore --start 2026-10-01 --end 2026-10-19 --out exports
    python -m pipeline.corrections --record-id ID --set dht_temp_c=30.1 --reason "..." --author NAME

Firestore credentials come from `GOOGLE_APPLICATION_CREDENTIALS` (a file kept outside the repo)
and `PRISM_FIREBASE_PROJECT`. Proposed firmware changes: `../docs/FIRMWARE_PROPOSAL_sensor_v2.md`.

## Rule-based and statistical assessments (`assess/`, not trained models)

- `assess.thi_band.assess_thi`: B1 THI band with hysteresis.
- `assess.growth.assess_growth` and `add_pen_comparison`: A1 growth trend from the pig's own weigh-ins.
- `assess.pen_thermal.assess_pen_thermal`: A2 pen-level thermal flag.

All settings live in `config/assessment.json`, all wording in `config/labels.json`.
`null` values return `not_configured`. The optional benchmark file is
`config/pic_2019_commercial_benchmark.csv` (columns `age_days,weight_kg,use`); only rows with
`use=context_only` are loaded, and they are used for display only.

## B2 forecasting experiment (offline, real data only)

    python -m forecast.run --dataset exports/<dataset_version>   # real Phase-1 export
    python -m forecast.run --pipeline-test                       # synthetic; "PIPELINE TEST ONLY, NOT VALID RESULTS"

All settings are in `config/forecast.json`: horizons, features, splits, pre-declared grids, seed,
bootstrap and the acceptance rule. They must be fixed before results are seen. The run stops
when there are too few independent days. Reports go to `reports/forecast/<dataset_version>/`
as `report.json` and `report.md`. No model is enabled unless the team's `acceptance_rule`
passes on real data.

## API (app/)

| Route | Access | Purpose |
|---|---|---|
| `GET /health` | public | liveness (unchanged) |
| `GET /ready` | public | readiness: auth configured, forecast model active / none / load_failed |
| `POST /predict/farm`, `POST /predict/pig-growth` | x-api-key (unchanged) | old tree models; deprecated |
| `POST /api/farm/analyze`, `POST /api/pig/analyze` | signed-in user | the calls the Flutter app already makes |
| `POST /assess/environment` | signed-in user | B1 THI band plus B2 forecast when an approved model is active |
| `POST /assess/pig-growth` | signed-in user | A1 growth trend |
| `POST /assess/pen-thermal` | signed-in user | A2 pen thermal flag |
| `GET /models`, `GET /models/active`, `GET /models/{v}/evaluation` | admin | model info |
| `POST /models/{v}/activate`, `POST /models/rollback` | admin | switch the active model |

Auth uses the Firebase ID token the app already sends. It needs `pip install -r requirements.txt`
and `PRISM_FIREBASE_PROJECT=<project id>`; no service-account key is needed to verify tokens.
The admin role is a custom claim: `python -m app.admin_claims grant <uid>` (needs a service-account
key kept outside the repo). Without auth configured, protected routes return 503 (fail closed).

Models are packaged with `python -m forecast.register` into `models/registry/<version>/`, and the
active version is in `models/registry/ACTIVE.json`. The API never sends sprinkler commands.

## Operations guide

Setup, environment variables, the full API reference, export, experiment, retrain/approve/
activate/rollback, monitoring and limitations are in `../docs/PRISM_ML_GUIDE.md`.
