# Baseline audit (before changes), 2026-10-12

Scope: branch `thermal_heat_map_parado` at commit `665c484`, the capstone paper, the firmware source
the team shared, and earlier ML attempts found on the development machine. This records the state
**before** any change in this implementation.

## Sources inspected

| Source | Location | Notes |
|---|---|---|
| Capstone paper (Ch. 1–3) | `Downloads/PRISM-CAPSTONE-CHAPTER-1-3-CODE-VIBERS.pdf` (2026-05-06) | Authoritative paper. `Chapter-1-5_CAPSTONE-FINAL.pdf` belongs to a different capstone (oyster-mushroom "Kabute" system) and was not used. |
| Flutter app | `lib/` | Dashboard, temperature/humidity monitoring, pig profiles |
| ML service (tracked) | `prism-ml2.0/` | FastAPI + 2 Decision Trees |
| ML attempts (untracked) | `prism-ml/` (venv + `.pyc` only), `Downloads/prism-ml/`, `C:/src/PRISM_ML_BACKUP` (pre-history-cleanup bundle) | Earlier HotPig/INRAE work |
| Firmware | `Downloads/prismarduino.txt` (2026-10-10), not in the repo | See "firmware version mismatch" |
| Cloud Functions | `functions/index.js` | Scheduled stock/expiry/intake checks; sensor threshold alerts |
| Firebase config | `firebase.json`, `.firebaserc`, `google-services.json`, `lib/firebase_options.dart` | No Firestore rules in the repo |

## What the paper requires (and notes)

* Classify farm/thermal condition as **Good / Needs Attention / High Risk** with a scikit-learn Decision
  Tree (Table 4), and generate actionable recommendations. Paper says "TensorFlow" also supports it;
  nothing in the code uses TensorFlow.
* AMG8833 measures pig **surface** temperature (paper 1.2.4, 3.x). The Limitations section says
  "humidity … not measured", which contradicts the DHT22 in Tables 2/8 and the app. This implementation
  follows the hardware actually used (DHT22 present).
* The system "does not perform medical diagnosis and does not replace professional veterinary
  assessment" (Limitations). This is the basis of the insight wording.
* Specific objective 2 is sensor calibration. **The project is currently in that phase, and Firebase
  holds no clean, real data.**
* The sprinkler is never activated automatically by a heat alert, only by user action or schedule
  (1.2.4). The insights therefore *suggest* misting; they never trigger it.

## Findings

### Synthetic / fabricated / rule-based ML (critical)

1. `prism-ml2.0/ml/make_datasets.py` generates 8,000 **synthetic** farm rows and 8,000 synthetic pig
   rows with NumPy random numbers. Labels are produced by hand-written rules (`farm_label()`: THI level +
   body-surface level; `growth_label()`: ±10 % of a reference curve). The Decision Tree re-learns the
   rule, so `farm_model_meta.json`'s accuracy of 0.9988 and macro-F1 of 0.9989 measure agreement with
   the rule, not performance on pigs.
2. Body-surface bands 35.5/37.0 °C and the THI-level scoring are marked `[PROJECT-DEFINED]` and were
   never validated.
3. `Downloads/prism-ml/` uses 1,000–1,420 rows of synthetic farm data (`prism_farm_dataset*.csv`).
4. The earlier HotPig/INRAE attempt (bundle commit `4b69b88`, "ML w/out synthetic data") predicted the
   **experimental period** (TN / HS), which is a different task from current thermal status. Its own
   leakage audit found `stage` encodes the period (macro-F1 0.72 with stage, 0.49 "physiology only").
   HotPig grouped-CV macro-F1 was 0.21–0.27.

### Client/backend/firmware contract mismatches (critical)

5. The Flutter `MlService` called `/api/farm/analyze` and `/api/pig/analyze`, which `prism-ml2.0` does not
   serve (`/predict/farm`, `/predict/pig-growth`). It also sent a different body. **No ML result could
   reach the app.**
6. The dashboard sent a **placeholder 25 °C** when no room temperature was available, and the humidity
   page sent `tempLive ?? 25.0`. `FarmDataService.getFarmMLInputs()` substituted **28 °C / 75 % RH**
   when there were no readings. Invented inputs could have produced a reassuring status.
7. On error, the dashboard displayed the raw exception text (`e.toString()`) to farmers.
8. The dashboard ("Pig Status") and temperature page labelled the AMG8833 **surface** reading as
   Low/Normal/High using 38.7–39.8 °C, which are core/rectal norms. That is a threshold classification
   in the app, inconsistent with the backend and physically inappropriate.
9. **Firmware version mismatch:** `prismarduino.txt` writes `ambientTemp` (filled with the AMG8833
   *maximum pixel*), `humidity`, `temperature_second` and `humidity_second`. It never reads the
   DHT22's temperature channel. The app reads `pigBodyTemp`, `ambientHumidity`, `ambientTemp` (treated
   as DHT22 room temperature) and `sensor_readings_seconds`. The deployed firmware must therefore be a
   different, newer version than the file inspected. It could not be inspected and was not tested.
   **Update 2026-10-12:** the team supplied the deployed firmware (`prismoct12.txt`). It reads the DHT22
   temperature into `ambientTemp` and writes `pigBodyTemp` (AMG8833 maximum pixel), `ambientHumidity`,
   `live_sensor/latest`, `sensor_readings_seconds` and `sensor_readings_hourly`, matching the app. Still open
   in it: `waterValid` is always `true` (no echo → 0 % "Empty"); unauthenticated Firestore REST with the web
   API key and `setInsecure()`; hard-coded Wi-Fi credentials; `sensor_readings_seconds` stores no thermal frame.
10. `functions/index.js` `onLiveSensorUpdate` reads `tempAvg`, which neither firmware nor app writes, so
    temperature alerts could never fire.
11. The firmware sets `waterValid = true` unconditionally and reports 0 % ("Empty") when the ultrasonic
    sensor returns no echo, so a sensor fault looks like an empty tank.
12. Thermal history is not stored: the full 64-pixel frame exists only in `live_sensor/latest`, which is
    overwritten. No training data with thermal frames can be reconstructed from Firestore.

### Security

13. **The ESP32 reads and writes Firestore unauthenticated** using only the web API key
    (`?key=AIza…`), with `client.setInsecure()` (no TLS certificate validation). Writing therefore
    requires Firestore rules that allow unauthenticated writes to sensor and sprinkler documents. Anyone
    holding the (public) API key can forge readings or switch the sprinkler.
14. No `firestore.rules` exists in the repository; the deployed rules are unknown.
15. Firmware source contains the Wi-Fi SSID/password in plain text. It is not in the repo, but if it
    is shared or committed, rotate the Wi-Fi password.
16. Firebase web/Android API keys are in `google-services.json` and `firebase_options.dart`. These are
    client identifiers, not secrets, but they should be restricted (Android package + SHA-1, API
    allow-list) in the Google Cloud console.
17. `MlService` base URL was a hard-coded LAN `http://` address (cleartext).
18. Release builds are signed with the **debug keystore** (`android/app/build.gradle.kts`, password
    `android`), and `debug.keystore` plus `local.properties` are committed.
19. `.firebaserc` default project `prism-capstone-svncte` differs from the app's `prism-3cd2c`, so
    `firebase deploy` would target the wrong project.
20. `prism-ml2.0` API: an optional single shared API key (none if unset), no rate limiting, no payload
    limits, and it loads pickle files.
21. All sensor collections are global (single farm/device). Every signed-in user can see every
    reading, and `onLiveSensorUpdate` sends one device's alerts to every admin.

### Tests

22. `test/widget_test.dart` is fully commented out (fails to load: no `main`). `prism-ml2.0/tests/smoke_test.py`
    asserts the synthetic rule's own outputs.
