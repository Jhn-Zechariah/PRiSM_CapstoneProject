# PRISM forecasting model

Forecasts the **pig surface temperature** read by the AMG8833 **15 and 30 minutes ahead**
from the last hour of sensor data, then maps the forecast to **Good / Needs Attention /
High Risk** for the app. It replaces the old rule-based Decision Tree (archived in
`legacy/decision_tree/`).

> This is a monitoring and decision-support tool. It does **not** diagnose disease and does
> not replace a veterinarian.

## Contents

| File | Purpose |
|---|---|
| `config.yaml` | Every range, cutoff and simulator parameter (nothing range-related is hard-coded) |
| `common.py` | Config loading, paths, Firestore client (credentials from env vars only) |
| `sanity.py` | Physical-limit check, range report, out-of-envelope warning, live-window check |
| `preprocess.py` | 10-second docs → regular 1-minute frame; gap filling; sprinkler minutes from logs |
| `features.py` | THI (`compute_thi`), lags, rolling stats, time-of-day, sprinkler features, targets |
| `simulate.py` | Phase 1 synthetic data generator (physics, not labels) |
| `datasets.py` | Loads synthetic/real data and splits it by time |
| `train.py` | Tunes and compares the 4 candidate models, saves the best |
| `evaluate.py` | Metrics, risk-class recall, lead time, noon-peak error, plots |
| `model_io.py` | Save/load/predict/archive/promote model bundles |
| `api.py` | FastAPI service: `GET /predict`, `GET /health` |
| `export_firestore.py` | Pulls historical readings + sprinkler logs to `data/real/` |
| `analyze_real_data.py` | Percentiles and cutoff hit-rates to support recalibration |
| `retrain.py` | Runs Phase 1/2/3 end to end, archives the previous model, rollback |
| `check_connection.py` | Confirms Firestore access (prints field names/types only) |
| `tests/` | Unit tests (`pytest`) |
| `models/current_model.joblib` | The deployed model |
| `reports/` | Metrics JSON and plots |

## Setup (Windows, from the repo root)

```powershell
cd prism-ml
python -m venv venv
venv\Scripts\activate
pip install -r requirements-dev.txt
pytest                       # 36 tests, no network needed
```

### Credentials

Never put the service-account key in the repo, and never paste its contents anywhere.
The code reads credentials from environment variables only:

| Variable | Used for |
|---|---|
| `GOOGLE_APPLICATION_CREDENTIALS` | **Local:** path to the key file, which lives outside the repo |
| `FIREBASE_CREDENTIALS_JSON` | **Railway:** the key's JSON *text* (loaded in memory, never written to disk). Takes priority if both are set. |
| `PRISM_API_KEY` | Shared secret clients send in the `X-API-Key` header. Required by `/predict`. |
| `PRISM_MODEL_PATH` | Optional. Defaults to `models/current_model.joblib`. |

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS = "C:\keys\<your-key>.json"   # outside the repo
$env:PRISM_API_KEY = "<a long random string>"
```

## Commands

```powershell
python check_connection.py                 # 1. confirm Firestore access (~2 reads)
python simulate.py                         # 2. synthetic data -> data/synthetic/
python train.py --data synthetic --promote # 3. train, compare, report, install as current
python evaluate.py --data synthetic        # 4. re-evaluate the current model
uvicorn api:app --reload                   # 5. serve the API on http://127.0.0.1:8000
python export_firestore.py --start 2026-10-20   # 6. export real data (resumable)
python analyze_real_data.py                # 7. percentiles + cutoff hit-rates
python retrain.py --phase 2                # 8. retrain (see "Retraining workflow")
```

`train.py` also accepts `--data real` and `--data combined`. Combined training weights real
rows by `training.sample_weight_real` (default 3x).

## Data and schema (unchanged; the ESP32 and the app keep using it)

| Collection | Fields used | Notes |
|---|---|---|
| `sensor_readings_seconds/s<epoch>` | `timestamp` (Firestore Timestamp, UTC), `pigBodyTemp`, `ambientTemp`, `ambientHumidity` | One doc per 10-second slot. An invalid sensor's field is omitted. |
| `live_sensor/latest` | `sprinkler` (bool) | Current sprinkler state, read by the API |
| `sprinkler_logs/<auto>` | `timestamp` (run **start**), `durationSec` | Written after each run ends |

Assumptions:
- `pigBodyTemp` is the hottest of the AMG8833's 64 pixels, after the firmware's −3.11 °C
  calibration. It is a pen-level value, not per pig.
- History docs don't store the sprinkler state, so ON/OFF per minute is rebuilt from
  `sprinkler_logs`. The firmware's log queue holds 8 runs, so runs can be lost during long
  WiFi outages.
- Timestamps are UTC. Time-of-day features use `project.timezone` (Asia/Manila).

## Method

1. **Pre-processing**: physical-limit check → 1-minute mean → gaps up to 5 min interpolated
   → longer gaps marked missing. Any training window touching a long gap is dropped.
2. **Features at minute t** (only data at or before t): current readings, THI, gap
   (pig − ambient), lags of 5/10/15/30 min, 15- and 30-min rolling mean/max/rate of change,
   time of day (sin/cos), sprinkler state, minutes since the last spray.
3. **Targets**: the change in `pigBodyTemp` from t to t+15 and t+30. Predicting the change
   instead of the level helps tree models stay sensible near the edges of their training
   range. The forecast is current value + predicted change.
4. **Models**: persistence (no change), Ridge, Random Forest and LightGBM. Each is tuned with
   `TimeSeriesSplit` on the training days. The lowest mean validation MAE wins (the choice is
   automatic and logged). The winner is refit on train+validation and tested once.
5. **Splits** are by whole days in time order, never shuffled. For real data, the latest
   `real_holdout_days` are frozen in `models/real_holdout.json` and never trained on.
6. **Risk mapping** (presentation only): the higher of the two forecasts is compared with
   the `risk` cutoffs in `config.yaml`.

## Reference ranges and the field mismatch

| | Ambient temp | Humidity | Pig surface (AMG8833) |
|---|---|---|---|
| A. Normal band (paper/team) | 15.6–23.9 °C *(team-provided, citation needed)* | 60–70 % | 34–37 °C |
| B. Observed in the field | 26–32 °C | 67–96 % | 27–35 °C |
| Training envelope (A ∪ B + margin) | 14.6–33.5 °C | 57–99 % | 26–40 °C |

Real readings sit mostly outside band A: warmer, more humid, and the AMG8833 reads lower
than the literature skin range (likely distance and 8x8 resolution). The simulator
therefore produces both regimes:
- **cool/normal days** follow band A, with the AMG reading bias at 0;
- **warm, hot and cloudy/rainy days** cover band B. Each spell is randomly either "paper"
  (bias 0, so heat-stress readings above 37 °C occur) or "field" (`amg8833_reading_bias`
  4–6.5 °C, plus occasional "pig out of view" episodes where the hottest pixel drops toward
  air temperature). The out-of-view part is a **hypothesis** to check against real data.

`amg8833_reading_bias` must be tuned once a reference thermometer reading or enough real
data exists.

### Known limitation: the risk cutoffs may never trigger on real readings

`Needs Attention` starts above 37.0 °C (top of band A) and `High Risk` at 38.5 °C
(**placeholder**). The AMG8833 currently reads 27–35 °C in the field, so these
literature-based cutoffs may rarely or never fire on real data, and the app would always
show "Good". `analyze_real_data.py` prints the real percentiles of pig temperature and of
the gap, and the share of readings above each cutoff, so the team can decide on a
recalibration (for example sensor-relative cutoffs validated with a reference thermometer
or observed pig behaviour). The cutoffs are **not** changed automatically.

## Phase 1 results (SYNTHETIC DATA: pipeline sanity check only)

> These numbers come from **simulated data** and only show that the pipeline works end to
> end. They are **not** the accuracy of the real PRISM system. Only the frozen real hold-out
> block can support a performance claim. Full report: `reports/metrics_synthetic_20261026.json`.

90 simulated days (seed 42): 62 days train, 14 validation, 14 test (2026-03-22 to 2026-04-04).

**Model selection (validation MAE, °C, mean of t+15/t+30):** persistence 0.406, Ridge 0.371,
**Random Forest 0.365 (selected)**, LightGBM 0.426.

| Test (synthetic) | MAE | RMSE | Persistence MAE | Persistence RMSE |
|---|---|---|---|---|
| t+15 | 0.196 | 0.349 | 0.229 | 0.399 |
| t+30 | 0.244 | 0.421 | 0.291 | 0.521 |

- **Risk level as shown in the app** (worse of the two horizons): accuracy 0.966; recall
  Good 0.998, Needs Attention 0.847, High Risk 0.850.
- **Noon peak (11:00–14:00) vs rest of day, MAE:** t+15 0.189 vs 0.197; t+30 0.229 vs 0.246.
- **Early-warning lead time:** no sustained crossings into Needs Attention in the test days.
  For 3 crossings into High Risk the lead was 1, 0 and 1 minutes, i.e. essentially no
  advance warning (see Limitations).
- **Range coverage of the training data:** pig surface 47 % in band A, 60 % in band B,
  99.6 % in the envelope; ambient 33 / 56 / 99.99 %; humidity 35 / 73 / 100 %.
- **Synthetic-to-real transfer:** not yet available (no real data exported).
- The winning model depends on the simulator settings. While tuning the simulator, one
  noisier setting (more frequent out-of-view episodes) made Ridge win, and it did not beat
  persistence at t+30. The automatic selection is reliable; the ranking on synthetic data
  is not evidence about real data.

Plots: `reports/synthetic_20261026_day.png` (forecast vs actual),
`..._error_by_hour.png`, `..._feature_importance.png`.

## API

`GET /predict` (header `X-API-Key: <PRISM_API_KEY>`):

```json
{
  "status": "ok",
  "message": "Forecast computed from the latest readings.",
  "latest_reading_at": "2026-10-26T06:00:00Z",
  "generated_at": "2026-10-26T06:00:12Z",
  "predicted_pig_temp_15min_c": 33.42,
  "predicted_pig_temp_30min_c": 33.61,
  "risk_level": "Good",
  "recommendation": "Conditions are expected to stay within the normal range. Continue regular monitoring.",
  "current": {"pig_surface_temp_c": 33.2, "ambient_temp_c": 29.1, "humidity_pct": 81.0,
              "thi": 82.4, "sprinkler_on": false},
  "model_version": "random_forest-synthetic-202610260842",
  "synthetic_only_model": true,
  "cached": false,
  "disclaimer": "Forecast to support monitoring decisions only. It does not diagnose disease or replace a veterinarian."
}
```

| `status` | HTTP | Meaning | Forecast fields |
|---|---|---|---|
| `ok` | 200 | Forecast computed | set |
| `insufficient_data` | 200 | Fewer than 31 continuous minutes in the last hour | `null` |
| `stale_data` | 200 | Newest reading is older than `api.stale_after_min` (5 min) | `null` |
| `out_of_training_range` | 200 | Live readings outside the training envelope | `null` |
| `model_unavailable` | 503 | No model file loaded | `null` |
| `firestore_error` | 503 | Firestore could not be read | `null` |
| — | 401 | Missing or wrong `X-API-Key` | — |

`GET /health` (no key) returns service status, model name/version/data source and uptime.

**Read budget.** A cold start reads the last hour once (~360 docs). After that, each
refresh reads only the docs newer than the last one seen (~5 per 45 s), plus
`live_sensor/latest` (1), plus `sprinkler_logs` every 5 minutes. Answers are cached for
`api.cache_ttl_s` (45 s), so any number of phones share one refresh. If the service sits
idle for longer than the window, it re-seeds the hour rather than reading the whole gap.
Predictions are never written anywhere.

## Deploying on Railway

1. New service from this GitHub repo. Set **Root Directory** to `prism-ml`.
2. Railway installs `requirements.txt` and uses `.python-version` (3.13). Start command
   (also in `Procfile`): `uvicorn api:app --host 0.0.0.0 --port $PORT`
3. Variables: `FIREBASE_CREDENTIALS_JSON` (paste the key's JSON text in Railway's variable
   editor, not in the repo), `PRISM_API_KEY`, optionally `PRISM_MODEL_PATH`.
4. Commit `models/current_model.joblib` (~6 MB) so the build contains it. Never commit
   credentials or bake them into an image.
5. Check `https://<service>.up.railway.app/health`.

## Flutter integration (not yet changed in the app)

The app still calls the old `/api/farm/analyze` in `lib/core/services/ml_service.dart`
(`analyzeFarm`), used by `Dashboard_Screen.dart` and reading `condition` and
`recommendations`. To switch:

- **`ml_service.dart`:** set `baseUrl` to the Railway URL. Replace `analyzeFarm` with a
  `GET $baseUrl/predict` call with header `X-API-Key`; there is no request body, because the
  server reads Firestore itself.
- **`Dashboard_Screen.dart`:** read `status` first. Show `risk_level`,
  `predicted_pig_temp_15min_c`/`30min_c` and `recommendation` only when `status == "ok"`.
  Otherwise show `message` (no data / sensor offline / outside training range).
  Always show `disclaimer`, and label the result as a prototype while
  `synthetic_only_model` is true.
- **Caveat:** a key shipped inside a mobile app can be extracted. It deters casual abuse but
  isn't strong protection. Verifying Firebase ID tokens on the server is the stronger option
  if needed later.

## Retraining workflow

| Phase | When | Command | What happens |
|---|---|---|---|
| 1 | Now | `python retrain.py --phase 1` | Train on synthetic data and deploy as a prototype |
| 2 | About 1–2 weeks of real data (`min_real_days_phase2`) | `python export_firestore.py` then `python retrain.py --phase 2` | Train on combined data (real weighted 3x), test on the frozen latest real days, promote only if better than the deployed model |
| 3 | 2–3+ weeks of real data | `python export_firestore.py` then `python retrain.py --phase 3` | Train on real data only, compare with the synthetic-trained model and the deployed one on the same hold-out days, keep the best |

- Every promotion first copies the previous model to `models/archive/model_<UTC time>_<version>.joblib`.
  Use `python retrain.py --list` to list them and `python retrain.py --rollback <file>` to restore one.
- As soon as real data exists, `train.py --data synthetic` (or `evaluate.py --data transfer`)
  also reports the **synthetic-to-real transfer** result: the synthetic-trained model scored
  on real data it has never seen.
- Only the frozen real hold-out block is a valid performance claim for the real system.
- `export_firestore.py` stops and asks for `--yes` before any export above 50,000 documents.
  One day of data is ~8,640 documents.

## Limitations

- **Phase 1 numbers are synthetic.** They show the pipeline works, not how accurate PRISM
  is in a real pen.
- **The simulator encodes assumptions:** response speed, spray effect, the AMG bias and the
  out-of-view hypothesis. All are in `config.yaml` and need checking against real data.
- **The literature ranges and the field readings disagree** (see above). The risk cutoffs
  above 37 °C are placeholders.
- **There is little early warning.** On synthetic data the model rarely raises a forecast
  above a cutoff before the reading itself crosses it, because regressors trained to
  minimise average error under-predict sharp rises. Options for later: a lower "forecast"
  cutoff, or a quantile (upper-bound) model for alerts.
- **The AMG8833 gives one pen-level value** (the hottest pixel), not one per pig. It can't
  separate pigs or detect a single sick animal.
