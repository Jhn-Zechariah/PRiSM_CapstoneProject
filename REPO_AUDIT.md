# PRISM Repository Audit (Phase 0, no code changes)

- **Audit date:** 2026-10-19
- **Branch inspected:** `earl_branch2.0` (working tree clean; latest commit `06ae1f2`)
- **Scope:** every tracked file on this branch, plus a search of all local and remote branches for firmware and rules files.

**Legend:** **[VERIFIED]** = read in code or reproduced by running it. **[UNVERIFIED]** = cannot be confirmed from this repository; the reason is given.

---

## 0. Headline findings

| # | Finding | Evidence |
|---|---|---|
| H1 | **The Flutter ML client and the FastAPI backend do not match. Every ML call from the app returns 404.** The app calls `/api/farm/analyze` and `/api/pig/analyze` with a Firebase `Authorization: Bearer` token. The backend only serves `/health`, `/predict/farm` and `/predict/pig-growth`, and uses `x-api-key` auth. The app was written for the old `prism-ml/prism_api.py`, which commit `85c908e` deleted. | `lib/core/services/ml_service.dart:38,103`; `prism-ml2.0/app/main.py:32-45`; run locally (see §9): both app routes → `404`. |
| H2 | **The app treats AMG8833 data as a per-pig, core-body temperature.** The field is named `pigBodyTemp`. The dashboard labels pig status `Low` / `Normal` / `High` using core/rectal thresholds of 38.7 / 39.8 °C. The Cloud Function alert says "Body temperature is …". | `lib/features/dashboard/presentation/pages/Dashboard_Screen.dart:1039-1041`; `functions/index.js:333` |
| H3 | **The farm model requires `body_temp` as an input and is trained to label risk partly from it.** This conflicts with the fixed fact that no per-pig temperature exists. | `prism-ml2.0/app/main.py:20`; `prism-ml2.0/ml/features.py:90,103-110` |
| H4 | **All training data is synthetic.** The metrics stored with the models (accuracy 0.9988 and 1.0) come from a decision tree re-learning the rule that generated its own labels. They are not evidence of real-world performance. | `prism-ml2.0/ml/make_datasets.py:1`; `prism-ml2.0/README.md:6`; `prism-ml2.0/models/*_meta.json` |
| H5 | **There is no ESP32 firmware and no Firestore security rules file on any branch.** ESP32 behavior can only be inferred from what the app reads. Database security is unverified. | Search of all `refs/heads` and `refs/remotes` for `*.ino`, `platformio.ini`, `*.rules`, `firestore.rules`: no results. |
| H6 | **No automated tests run for Flutter or Cloud Functions.** `test/widget_test.dart` is entirely commented out and fails to load. | §9 |

---

## 1. Architecture summary

| Layer | Location | Notes |
|---|---|---|
| Flutter app | `lib/`, `pubspec.yaml` | Dart SDK `^3.11.0`; Flutter 3.41.7 installed locally. State via `flutter_bloc`. Firebase: `firebase_core ^3.10.1`, `firebase_auth ^5.5.0`, `cloud_firestore ^5.6.2`, `firebase_messaging ^15.2.2`. Feature folders: `auth`, `dashboard`, `feeding`, `medication`, `monitoring`, `pig_management`. |
| Firebase | `lib/firebase_options.dart`, `android/app/google-services.json`, `firebase.json`, `.firebaserc` | **Cloud Firestore** is the only database in use. No Realtime Database usage was found. Auth: email/password, Google, Facebook (`lib/features/auth/data/firebase_auth_repo.dart`). FCM push notifications. |
| Cloud Functions | `functions/index.js`, `functions/package.json` | Node 24, `firebase-functions ^7.0.0`, `firebase-admin ^13.6.0`. Four functions: three daily schedules (stock, expiry, intake) and the `onLiveSensorUpdate` Firestore trigger. |
| ML backend | `prism-ml2.0/` | FastAPI + scikit-learn decision trees. `Procfile`: `uvicorn app.main:app --host 0.0.0.0 --port $PORT`. |
| ESP32 firmware | **Not in repo** **[UNVERIFIED]** | Behavior inferred from the Flutter code only (see §2 and §7). |
| Hosting / deployment | **[UNVERIFIED]** | `Procfile` plus `prism-ml2.0/flutter_snippets/ml_service.dart:6` (`https://YOUR-APP.up.railway.app`) suggest Railway is intended, but no deployment is configured. The app is hard-coded to the LAN address `http://192.168.1.130:8000` (`lib/core/services/ml_service.dart:7`). |

**Firebase project ID inconsistency [VERIFIED]:**
- `firebase.json` and `lib/firebase_options.dart:53,63` use `prism-3cd2c`.
- `.firebaserc` still defaults to `prism-capstone-svncte`.
- As a result, `firebase deploy --only functions` would target the **old** project unless `--project` is passed.
- `firebase.old.json` keeps the old configuration.

**Stray files:** `.sfdx/` (Salesforce tooling) and a root `requirements.txt` (UTF-16 encoded `firebase_admin==7.4.0` stack) appear unrelated to the current backend. The root `requirements.txt` looks left over from the deleted `prism-ml/`.

---

## 2. Data flow (ESP32 → app / Firebase)

All of this is inferred from Flutter code. **The firmware is not available, so the ESP32 side of every item is [UNVERIFIED].**

| Item | What the app expects | Evidence |
|---|---|---|
| Live push target | Firestore document `live_sensor/latest`, overwritten in place (single document, not keyed per reading). | `Dashboard_Screen.dart:58-61,268,326` |
| Push interval | "ESP32 pushes to every 10s" (code comment only). | `Dashboard_Screen.dart:60,82` |
| LAN endpoint | `GET http://<esp32Ip>/sensor` returns the same JSON. The app polls it every 5 s with a 2 s timeout, then falls back to Firestore. The default IP `192.168.1.8` is updated from the payload's `ip` field. | `Dashboard_Screen.dart:18,219,386-391` |
| AMG8833 payload | **The raw 8×8 frame is sent**: `thermalPixels` is a list of 64 numbers, used only for the live heat-map. Comment: "Only the newest frame is kept; no thermal history is stored." The ESP32 also sends a summary value `pigBodyTemp` plus `pigBodyTempValid`. **How firmware derives `pigBodyTemp` (max? mean?) is [UNVERIFIED].** | `Dashboard_Screen.dart:1100-1108,1023-1025` |
| Other live fields | `ambientTemp`, `ambientTempValid`, `ambientHumidity`, `ambientHumidityValid` (DHT22); `waterPct`, `waterStatus` (HC-SR04); `sprinkler` (bool); `tempStatus`, `pigStatus` (strings computed by firmware); `lastActivated`, `date`, `duration`; `ip`; `timestamp` (NTP; firmware sends `1970-01-01T00:00:00Z` if NTP fails). | `Dashboard_Screen.dart:74-80,1005-1098` |
| `tempAvg` / `humidity` | **Read by the Cloud Function from `live_sensor/latest` but never read by the app.** Whether firmware writes these field names is **[UNVERIFIED]**. If it does not, the IoT threshold alert never fires. | `functions/index.js:298-299` vs. app fields above |
| Per-reading history | Collection `sensor_readings_seconds`, queried by `timestamp` (Timestamp). Fields read: `pigBodyTemp`, `pigBodyTempValid`, `ambientHumidity`. Document ID scheme **[UNVERIFIED]**. | `temperaturemonitoring.dart:693-724,1182-1206`; `Dashboard_Screen.dart:1315-1330` |
| Hourly aggregates | `sensor_readings_hourly`, queried by `timestamp`, with fields `min`, `max`, `sum`, `count`. Written by firmware or an external process, not by anything in this repo **[UNVERIFIED]**. | `temperaturemonitoring.dart:1148-1170,1259-1264`; `humiditymonitoring.dart:1132` |
| Legacy hourly | `FarmDataService` reads `temperature_hourly.tempAvg` and `humidity_hourly.humidityAvg`, but **no code calls `FarmDataService`** (dead code). | `lib/core/services/farm_data_service.dart:18,48`; grep shows no callers |

---

## 3. Firebase (Firestore) structure

Inferred from reads and writes in code. Types are as written by the app; **values written by the ESP32 are [UNVERIFIED]**. No units are stored in any field: units are implied by field names such as `Kg` and `Pct`.

### Sensor and IoT
| Path | Fields (type, unit) | Writer |
|---|---|---|
| `live_sensor/latest` | see §2 (°C, %RH, % tank) | ESP32 [UNVERIFIED] |
| `sensor_readings_seconds/{id}` | `timestamp` Timestamp, `pigBodyTemp` num °C, `pigBodyTempValid` bool, `ambientHumidity` num %RH | ESP32 [UNVERIFIED] |
| `sensor_readings_hourly/{id}` | `timestamp`, `min`, `max`, `sum`, `count` | [UNVERIFIED] |
| `sprinkler_command/pending` | `state`: `"on"` / `"off"` | App (`Dashboard_Screen.dart:1551-1554`; also `temperaturemonitoring.dart:1533`, `humiditymonitoring.dart:1484`). The ESP32 is expected to read it **[UNVERIFIED]**. |
| `sprinkler_settings/config` | `isIotEnabled` bool, `isSprinklerAuto` bool, `schedule` string `"6:00 PM"`, `durationMins` int | App (`IoTControlsDialog.dart:189-197`). Comment: "Settings document the ESP32 reads". |
| `sprinkler_state/latest` | `lastActivated` str, `date` str, `duration` str, `status` `"ON"`/`"OFF"`, `activatedAt` Timestamp | App (`Dashboard_Screen.dart:530-545`) |
| `sprinkler_logs/{id}` | `timestamp` Timestamp, `type` (`"schedule"` or other), `durationSec` int | Read only (`sprinkler_logs_dialog.dart:474-536`). Writer is [UNVERIFIED] (likely ESP32). |
| `sensor_memory/latest` | `lastTemp`, `lastHumidity`, `tempMaxToday`, `tempMaxDate`, `humidityMaxToday`, `humidityMaxDate`, `lastPigStatus` | App UI cache (`Dashboard_Screen.dart:674-705`) |

### Users and notifications
| Path | Fields |
|---|---|
| `admins/{uid}` | `uid`, `username`, `email`, `createdAt`, `updatedAt` (`firebase_auth_repo.dart:26-37`); `fcmToken`, `tokenUpdatedAt` (`firestore_profile_repo.dart:107-109`); `notificationPreferences` map with keys `isNotifEnabled`, `isLowStockAlert`, `isMedExpAlert`, `isVaxSchedAlert`, `isHighTempAlert`, `isHighHumidityAlert` (keys from `functions/index.js`); `iotThresholds` map: `isIotEnabled`, `isSprinklerAuto`, `maxTemp`, `maxHumidity`, `schedule`, `durationMins` (`profile_cubit.dart:115-117`, `IoTControlsDialog.dart:205-212`); `iotAlertState.{tempAvg,humidity}` bool (`functions/index.js:337,356`) |
| `counters/{uid}` | `pigCount` int (`firestore_pig_repo.dart:59-62`) |

No notification documents are stored: notifications are FCM pushes only.

### Pig profiles and records (all manual entry)
| Path | Fields |
|---|---|
| `pigs/{pigId}` | `pigId`, `displayId` (`P-001`), `userId`, `breed`, `birthDate` Timestamp, `sex`, `birthWeightKg` num kg, `currentWeightKg` num kg, `notes`, `stage` (`Piglet` / `Nursery` / `Grower` / `Finisher` / `Mature`), `status` (`Normal/Healthy`, `Abnormal/Sick`, `Sold`, `Deceased`, …), `createdAt`, `updatedAt`, `lastIntakeDate`, `lastIntakeName` (`app_pig.dart:67-88`) |
| `pigs/{pigId}/weight_history/{id}` | `weightKg` num kg, `dateRecorded` Timestamp, `notes` (`"Birth weight"`, `"Initial weight"`, `"Manual update"`, `"Updated via Profile Edit"`). **No `source` field.** (`firestore_pig_repo.dart:66-80,111-116,179-183`) |
| `pigs/{pigId}/feeding_records/{id}` | `id`, `pigId`, `userId`, `feedType`, `amount` num (unit not stored; kg assumed in `farm_data_service.dart`), `timestamp` Timestamp. Older documents use an ISO string, which `app_feeding_record.dart:36-48` tolerates. |
| `pigs/{pigId}/medicine_intakes/{id}` | `pigId`, `userId`, `category` (e.g. `Vaccine`), `medName`, `dosage` str, `unitOfMeasurement`, `status` (incl. `Discontinued`), `nextSchedule` **Timestamp**, `purpose`, `dateTaken` Timestamp (`app_medicine_intake.dart:86-96`) |
| `medicines/{medId}` | `medId`, `userId`, `name`, `type`, `category`, `measurement_unit` (snake_case, unlike the other fields), `reorderLevel`, `totalStock` (`app_medicine.dart:25-32`) |
| `medicines/{medId}/medicine_stock/{id}` | `medicineId`, `expiryDate` **string**, `amount` (`app_medicine_stock.dart:21-23`) |

**Data-quality issues found [VERIFIED]:**
- **Fabricated birth weight:** every new pig gets a hard-coded `weightKg: 1.4` "Birth weight" record, regardless of the `birthWeightKg` the user entered. This makes `weight_history` contain fabricated data. (`firestore_pig_repo.dart:66-72`)
- **Type mismatch on `nextSchedule`:** the app now writes `nextSchedule` as a Timestamp (`app_medicine_intake.dart:12,94`). The Cloud Function `dailyIntakeScheduleCheck` still range-queries it as a `"YYYY-MM-DD"` string (`functions/index.js:205-219`) and parses it with `daysUntil()`, which only accepts strings (`:43-56`). Firestore does not match strings against Timestamps, so intake reminders for newly written intakes will not fire. Not run against live data **[UNVERIFIED in production]**.
- **Stage definitions disagree:**
  - App: five stages with cut-offs ≤21 / ≤70 / ≤120 / ≤170 days (`app_pig.dart:47-63`).
  - ML: three stages with cut-offs <70 / <126 days (`prism-ml2.0/ml/features.py:30-34`).

---

## 4. Existing ML code (`prism-ml2.0/`)

| Aspect | Detail |
|---|---|
| Training | `ml/make_datasets.py` generates data; `ml/train.py` trains `DecisionTreeClassifier(class_weight="balanced")` with `GridSearchCV` (max_depth 2–6, min_samples_leaf 5/10/20, 5-fold, macro-F1) and an 80/20 stratified split. It also runs an ablation and saves a tree PNG. |
| Inference | `app/predictor.py` loads `models/{farm_model,pig_growth_model}.pkl` with joblib, plus `*_meta.json` for the feature order. |
| Artifacts | `models/farm_model.pkl`, `farm_model_meta.json`, `farm_model_tree.png`, `pig_growth_model.pkl`, `pig_growth_model_meta.json`, `pig_growth_model_tree.png` (committed). |
| Farm model features | `body_temp`, `ambient_temp`, `humidity`, `thi` (`ml/features.py:118`) |
| Farm label | Rule `farm_label`: `thi_level` (0–3) + `body_level` (0–2) gives a score. Score ≥3 → `High Risk`, ≥1 → `Needs Attention`, otherwise `Good` (`ml/features.py:103-110`). |
| Pig model features | `age_days`, `stage`, `current_weight`, `previous_weight`, `days_between`, `weight_gain`, `adg_g`, `reference_weight`, `growth_ratio` |
| Pig label | Rule `growth_label`: `growth_ratio` <90 → Below, >110 → Above, otherwise Within (`ml/features.py:27,46-51`) |
| Thresholds and constants (all in **code**, not config) | THI formula (`features.py:77-81`); `THI_ALERT/DANGER/EMERGENCY = 75/79/84` (`:86`); `BODY_WARN/HIGH = 35.5/37.0` (`:90`); `BELOW_PCT/ABOVE_PCT = 90/110` (`:27`); PIC reference curve `REF_AGE`/`REF_WT`/`REF_ADG`, which the file itself marks "[CITE] Verify every value against the PDF" (`:14-22`); recommendation wording in `app/recommend.py`; disclaimer in `app/predictor.py:14-15`. |
| Recommendation logic | `app/recommend.py` contains rules on status, THI level, humidity >80, and ADG <0.8×reference. The text "Turn on cooling (sprinklers/fans) now" is **advisory text only**. No code path writes to Firebase or calls the pump. |
| Stored metrics | Farm: acc 0.9988 / macro-F1 0.9989 (ablation without `thi`: 0.9844). Pig: acc 1.0 / F1 1.0 (ablation: 0.7238). **These are fit-to-own-rule numbers on synthetic data; not reportable.** |
| Dependencies | `requirements.txt`: `scikit-learn==1.8.0`, `numpy==2.4.4`, `pandas==3.0.2`, `joblib==1.5.3` pinned. `fastapi`, `uvicorn[standard]`, `pydantic` are **unpinned**. The local venv has Python **3.13.1**, but `.python-version` says **3.12**. Installed: fastapi 0.142.2, pydantic 2.13.5. |

**Design issues relative to the fixed ML design:**
- The decision trees are near-perfect learned copies of hand-written rules (pig tree `max_depth: 2`). A classifier adds no information over evaluating the rule directly.
- The pig model compares weight to a commercial PIC curve as the **primary** label. The fixed design calls for the pig's **own weight trend** first, with the benchmark as context only.
- The pig model uses only two weigh-ins and ignores the rest of `weight_history`.
- Nothing implements B2 (forecasting) or A2 (pen-level thermal anomaly).

---

## 5. Training data provenance

**Everything is synthetic. No historical or verified real data exists in the repo.** Evidence quoted:
- `prism-ml2.0/ml/make_datasets.py:1`: `"""Builds the two synthetic training datasets."""`
- `prism-ml2.0/README.md:6`: `python -m ml.make_datasets   # build synthetic training data`
- `make_datasets.py:6-14`:
  - `rng = np.random.default_rng(42)`
  - `ambient = rng.normal(29, 4, N_FARM)`
  - `body = 33.5 + 0.2 * (ambient - 28) + rng.normal(0, 0.9, N_FARM)`
  - `elevated = rng.random(N_FARM) < 0.08`
- `make_datasets.py:31`: `weight = ref * rng.normal(1.0, 0.13)  # spread: calibrate from a cited source`

Labels come from the same rule functions the features encode (`farm_label`, `growth_label`), so the labels are **circular**.

The CSVs (`data/farm_dataset.csv`, `data/pig_growth_dataset.csv`, 8,000 rows each) carry **no `synthetic` tag** in their file names or columns.

Commit message `459faa4` ("ML w/out synthetic data …") refers to the deleted `prism-ml/` and does not describe current data.

---

## 6. API contract

### Backend as implemented (`prism-ml2.0/app/main.py`) [VERIFIED by running it]
| Route | Auth | Request | Response keys |
|---|---|---|---|
| `GET /health` | none | none | `status` |
| `POST /predict/farm` | `x-api-key`, only checked if env `PRISM_API_KEY` is set; otherwise open | `body_temp` 25–45, `ambient_temp` 5–55, `humidity` 0–100 | `status`, `thi`, `thi_level`, `confidence`, `recommendations`, `disclaimer` |
| `POST /predict/pig-growth` | same | `age_days` 0–400, `current_weight_kg`, `previous_weight_kg`, `days_between` 1–120 | `status`, `stage`, `growth_ratio_pct`, `reference_weight_kg`, `adg_g_per_day`, `reference_adg_g_per_day`, `recommendations`, `disclaimer` (or `status`, `message`, `disclaimer` when out of range) |

### What the Flutter app actually calls (`lib/core/services/ml_service.dart`)
| Method | Route | Body | Response keys read |
|---|---|---|---|
| `analyzeFarm` | `POST /api/farm/analyze` + `Authorization: Bearer <Firebase ID token>` | `temperature_c`, `humidity_pct`, `weight_change_kg`, `feed_intake_kg`, `medicine_given` | `condition`, `insights`, `recommendations` |
| `analyzePig` | `POST /api/pig/analyze` + Bearer | `pig_id`, `birth_date`, `current_weight`, `birth_weight` | `classification` (`normal` / `underweight` / `overweight`), `insight`, `recommendation` |

**Callers:**
- `analyzeFarm` is called from:
  - `Dashboard_Screen.dart:1426` (passes room temp, or a 25.0 placeholder, plus humidity)
  - `temperaturemonitoring.dart:2622` (passes the **AMG8833 `pigBodyTemp`** as `temperatureC`, see `:1333,1380`)
  - `humiditymonitoring.dart:2583`
- `analyzePig` is called from `pig_profile_card.dart:102`.

**Result:** route, auth scheme, request schema and response schema all differ.
- Every call returns 404, and the UI shows "Unavailable" or "ML analysis unavailable".
- `prism-ml2.0/flutter_snippets/ml_service.dart` matches the new backend but is **not wired into the app**.
- `pig_profile_card.dart` also never displays a disclaimer.

---

## 7. ESP32 behavior

**The firmware source is not in this repository on any branch. Everything below is inferred and [UNVERIFIED]:**
- Branches named `arduinoNiAustin`, `fixarduino`, `origin/testarduino` and `thermal_heat_map` contain only Flutter and ML files.
- **Sampling / push interval:** ~10 s, from code comments (`Dashboard_Screen.dart:60,82`).
- **Error handling:** the firmware sets `*Valid=false` flags for bad sensor reads (the app honors them), and falls back to an epoch timestamp when NTP fails (`Dashboard_Screen.dart:74-80`).
- **Offline buffering:** no evidence either way. If the ESP32 has no Wi-Fi, the app simply marks "Sensor Offline" (`Dashboard_Screen.dart:418-436`). **Unknown whether firmware buffers readings.**
- **Misting control:**
  - The app writes `sprinkler_command/pending.state` and also POSTs to `http://<esp32Ip>/sprinkler` on the LAN (`Dashboard_Screen.dart:1540-1554`).
  - Schedule and auto mode live in `sprinkler_settings/config` (`schedule`, `durationMins`, `isSprinklerAuto`, `isIotEnabled`).
  - The ESP32 reports state in `live_sensor.sprinkler` and can itself change `sprinkler_command/pending` ("sprinkler changed by ESP32", `Dashboard_Screen.dart:468`).
- **Where misting thresholds live:**
  - `maxTemp` / `maxHumidity` are saved only to SharedPreferences and `admins/{uid}.iotThresholds`. Only the Cloud Function uses them, and only for **notifications** (`functions/index.js:292-382`).
  - They are **not** in `sprinkler_settings/config`. Any temperature-triggered auto-misting threshold must therefore be hard-coded in firmware **[UNVERIFIED]**.
- **ML → pump:** **no path exists [VERIFIED]**. Neither the backend nor the ML response handlers in Flutter write `sprinkler_command` or call `/sprinkler`. Only explicit user taps do (`_confirmSprinkler`, `Dashboard_Screen.dart:1458+`).

---

## 8. Security

| Area | Status |
|---|---|
| Firestore rules | **No `firestore.rules` exists, and `firebase.json` has no `firestore` section.** Deployed rules are **[UNVERIFIED]**. |
| ESP32 access to Firestore | The ESP32 writes and reads fixed, user-independent documents (`live_sensor/latest`, `sprinkler_command/pending`, `sprinkler_settings/config`). That works only with open rules or a device credential. Which one is **[UNVERIFIED]**. If the rules are open, any client can toggle the pump. |
| Multi-tenancy | Sensor and sprinkler collections are global: one farm/device for all users. Pigs and medicines are filtered by `userId` in queries, but enforcement depends on the rules (unverified). `onLiveSensorUpdate` notifies **every** admin (`functions/index.js:306`). |
| App auth | Firebase Auth: email, Google (`serverClientId` in `lib/main.dart:33`), Facebook. |
| ML API auth | Backend: optional shared `x-api-key`; **open when `PRISM_API_KEY` is unset** (`main.py:11-16`). The app sends a Firebase ID token the backend does not verify. Served over plain `http://` on the LAN. |
| ESP32 LAN endpoints | `/sensor` and `/sprinkler` over unauthenticated HTTP **[UNVERIFIED on the device side]**. |
| Secrets | No service-account keys found in the working tree or in any commit on any branch (searched for `private_key"`, `*credential*`, `*.pem`, `*.env`). `firebase_credentials.json` and `.env` are git-ignored. `lib/firebase_options.dart` and `google-services.json` contain Firebase **client** API keys, which are public identifiers by design (not secrets). |
| Logging | `print`/`debugPrint` of full sensor payloads and auth errors (`ml_service.dart:19,25`; `main.dart:25,28,43`). Low risk, but noisy in release builds. |

---

## 9. Tests (actually run on 2026-10-19)

| Suite | Command | Result |
|---|---|---|
| ML smoke test | `prism-ml2.0/venv/Scripts/python.exe -m tests.smoke_test` | **8/8 PASS**, exit 0. It checks only that the models reproduce the rules on hand-picked inputs. There are no unit tests, no pytest, and no test of the HTTP layer. |
| API route probe | `uvicorn` on `localhost:8765`, then `curl` | `/health` 200; `/predict/farm` 200; `/predict/pig-growth` 200; **`/api/farm/analyze` 404**; **`/api/pig/analyze` 404**; `/predict/farm` with `body_temp=20` → 422 (the range check rejects valid cool-pen surface readings). OpenAPI paths: `['/health', '/predict/farm', '/predict/pig-growth']`. |
| Flutter tests | `flutter test` | **FAIL**, exit 1: `Failed to load "test/widget_test.dart": Missing definition of 'main' method` (the whole file is commented out). |
| Flutter analyze | `flutter analyze` | 39 issues: **0 errors, 0 warnings**, 39 info (lints such as `avoid_print` and `use_build_context_synchronously`). |
| Cloud Functions | none | `firebase-functions-test` is a devDependency, but no test files exist. |

`fastapi.testclient` could not be used because the venv lacks `httpx2`. I did not install it, to avoid modifying the environment in this phase.

---

## 10. Gaps and risks relative to the FIXED PROJECT FACTS

| # | Fixed fact violated / risk | Where |
|---|---|---|
| G1 | **Per-pig temperature assumption:** the field is named `pigBodyTemp`, the UI shows "Pig Status: Low/Normal/High", and the cut-offs 38.7/39.8 °C are core-temperature values applied to an ±2.5 °C surface sensor. | `Dashboard_Screen.dart:1023-1043,2196`; `sensor_memory.lastPigStatus` |
| G2 | **The ML farm model requires `body_temp`**, and `body_level` drives the label. | `ml/features.py:90,99-118`; `app/main.py:20` |
| G3 | **AMG8833 data is passed to ML as ambient temperature.** | `temperaturemonitoring.dart:1333-1380,2622` |
| G4 | The Cloud Function message calls the reading "Body temperature". | `functions/index.js:333` |
| G5 | **The app sends ML inputs the current design has no data for:** `weight_change_kg`, `feed_intake_kg` and `medicine_given` are always 0 or defaults. `FarmDataService` (which computed herd ADG from birth weight to current weight) is unused. Water level is not used by ML (fine), but feeding and healthcare are not reliable ML inputs. | `ml_service.dart:31-57`; `temperaturemonitoring.dart:2622-2627`; `farm_data_service.dart` |
| G6 | **Synthetic, circular training data** with near-perfect "metrics" stored beside the model. The data is not tagged synthetic. | §5 |
| G7 | **No `source` field** (`sensor` / `manual`) on any record. | `weight_history`, sensor collections |
| G8 | **Fabricated 1.4 kg birth-weight record** pollutes the weight history used for growth trends. | `firestore_pig_repo.dart:66-72` |
| G9 | Thresholds, reference curves and wording are hard-coded in Python and Dart, not in config files. | `ml/features.py`; `app/recommend.py`; `Dashboard_Screen.dart:1039` |
| G10 | The fixed ML design (B1, B2, A1, A2) is unimplemented: there is no own-trend ADG / stall detection, no forecaster, no thermal anomaly flag, and the per-pig thermal history needed for A2 is not stored (only `pigBodyTemp` per second; frames are discarded). | §4 |
| G11 | ML can command the pump: **no** [VERIFIED]. Only the "Turn on cooling" advice text exists. Keep it that way. | §7 |
| G12 | App/ML contract broken (H1); stage definitions disagree; `nextSchedule` type mismatch breaks reminders; `.firebaserc` project mismatch. | §3, §6, §1 |
| G13 | Security is unverifiable without the rules; the global device documents imply very permissive rules; the ML API is open by default. | §8 |
| G14 | Firmware is not under version control, so changes to ESP32 safety logic cannot be reviewed or reproduced. | §7 |

---

## 11. Phase-by-phase plan (files to add or change)

Ground rules for every phase:
- Existing Firestore fields are **only added to, never renamed or removed**.
- Pump, schedules, manual controls and ESP32 logic stay untouched unless you approve otherwise.
- Each phase ends with real test output.

### Phase 1: Safety and honesty fixes (no ML retraining)
| File | Change |
|---|---|
| `lib/features/dashboard/presentation/pages/Dashboard_Screen.dart` | Replace the 38.7/39.8 core-temp "Pig Status" with a neutral "Pen surface temp" label. Keep reading `pigBodyTemp` (field unchanged). Label wording comes from config (Phase 2). |
| `functions/index.js` | "Body temperature" → "Pen surface temperature (thermal sensor)". Fix `dailyIntakeScheduleCheck` to query `nextSchedule` as a Timestamp, keeping the string path for legacy docs. |
| `lib/features/pig_management/data/firestore_pig_repo.dart` | Use `pig.birthWeightKg` instead of `1.4`. Add `source: 'manual'` to new `weight_history` writes (additive). |
| `.firebaserc` | Align with `prism-3cd2c` (**needs your confirmation** of the correct project). |
| `prism-ml2.0/data/` | Rename or tag the CSVs as synthetic (e.g. `synthetic_*.csv` plus a `SYNTHETIC.md`). Move the metrics out of `models/*_meta.json`, or mark them `synthetic_fit_only`. |

### Phase 2: Configuration and data contract
| File | Change |
|---|---|
| `prism-ml2.0/config/thresholds.yaml` (new) | THI formula coefficients and bands, growth-trend thresholds (ADG floor, stall days, loss %), anomaly z-score, plus a citation/`project_defined` note on each value. |
| `prism-ml2.0/config/reference_curve.csv` (new) | PIC curve moved out of `ml/features.py`, marked context-only. |
| `prism-ml2.0/config/labels.yaml` (new) | All user-facing wording and the disclaimer. |
| `prism-ml2.0/ml/config.py` (new) | Loader. `ml/features.py` and `app/recommend.py` read from it. |
| `docs/DATA_CONTRACT.md` (new) | The Firestore schema in §3, with units and `source` semantics. |

### Phase 3: Model B (environment)
| File | Change |
|---|---|
| `prism-ml2.0/ml/thi.py` (new) | B1: rule-based THI band from DHT22 `ambientTemp` / `ambientHumidity` only. |
| `prism-ml2.0/ml/forecast.py` (new) | B2: simple interpretable regressor (persistence baseline vs. linear/ridge on lags and hour of day). Trained **only** on real `sensor_readings_seconds`/`hourly` exports. Must beat the persistence baseline, or ship the baseline. |
| `prism-ml2.0/ml/export_firestore.py` (new) | Read-only export script using a service account supplied via an env var path (never committed). |
| `prism-ml2.0/app/main.py`, `app/predictor.py` | Add `POST /v2/environment` (no `body_temp`). Keep `/predict/*` for compatibility, marked deprecated. |

### Phase 4: Model A (pig assessment)
| File | Change |
|---|---|
| `prism-ml2.0/ml/growth.py` (new) | A1: ADG over the full `weight_history`, flags for weight loss or stalled gain, optional PIC benchmark as context. Rules, not a trained tree. |
| `prism-ml2.0/ml/thermal_anomaly.py` (new) | A2: **pen-level** robust z-score of the AMG8833 summary vs. its own rolling baseline, adjusted for ambient temperature via a residual on `ambientTemp`. |
| `prism-ml2.0/app/main.py` | Add `POST /v2/pig/growth` (accepts a weight series) and `POST /v2/pen/thermal`. |

**Firmware needed for A2:**
- If A2 should use richer statistics than the existing per-second `pigBodyTemp`, firmware must add fields such as `thermalMax` / `thermalMean` to `sensor_readings_seconds` (additive).
- The firmware source must be provided first.

### Phase 5: Flutter integration
| File | Change |
|---|---|
| `lib/core/services/ml_service.dart` | Point at the `/v2/*` routes and a configurable base URL (`--dart-define`); keep the method signatures. |
| `pig_profile_card.dart`, `Dashboard_Screen.dart`, `temperaturemonitoring.dart`, `humiditymonitoring.dart` | Read the new response keys; always show the disclaimer; stop passing AMG data as `temperatureC`. |
| `lib/core/services/farm_data_service.dart` | Delete or repurpose (currently dead code). **Needs your approval.** |

### Phase 6: Security and deployment
| File | Change |
|---|---|
| `firestore.rules` (new) + `firebase.json` | Per-user rules for pigs and medicines; restricted device documents. **Requires knowing how the ESP32 authenticates. I cannot write safe rules without that.** |
| `prism-ml2.0/app/auth.py` (new) | Verify Firebase ID tokens (`firebase-admin`), with credentials only from environment variables. |
| `prism-ml2.0/requirements.txt`, `.python-version` | Pin `fastapi`, `uvicorn` and `pydantic`; align the Python version (3.12 vs. 3.13.1 in the venv). |

### Phase 7: Tests
| File | Change |
|---|---|
| `prism-ml2.0/tests/test_*.py` (new, pytest) | THI, growth and anomaly units; API tests via `TestClient`. Fixtures tagged `synthetic`. |
| `test/widget_test.dart` | Replace the commented-out file with real tests (models' `fromJson`, the label mapping). |
| `functions/test/*.test.js` (new) | `daysUntil`, Timestamp handling for `nextSchedule`, the alert debounce. |

---

## 12. What is missing to finish (needed from you)

1. **ESP32 firmware source.** Needed for push interval, buffering, how `pigBodyTemp` is computed, misting thresholds, and the device auth method.
2. **Currently deployed Firestore rules.** Export them from Firebase Console → Firestore → Rules.
3. **Read access to real data** for B2 and A2: a Firestore export or a service-account key kept outside the repo, passed by path in an env var.
4. **The ML backend hosting target and URL** (Railway?), and whether `PRISM_API_KEY` is set there.
5. **Confirmation of the Firebase project:** `prism-3cd2c` vs. `prism-capstone-svncte`.
6. **Citations** for the PIC curve and the THI bands, flagged `[CITE]` in `ml/features.py`.
