# Testing and validation

All results below were produced on 2026-10-12 on the development machine (Windows 11, Python
3.14.5, Flutter 3.41.8, Node 22.22, Java 21). Synthetic data appear **only** as clearly labelled software
test fixtures (`ml/tests/fixtures.py`, `data_origin=synthetic_test_fixture`). No metric from them is a
performance result.

## Commands

```bash
cd ml && .venv/Scripts/python -m pytest                       # Python: data, ML, API, security, contract, CLI
flutter test test/ml_service_test.dart test/ml_http_client_test.dart   # Dart client contract + CA pinning
# live TLS tests: set PRISM_TLS_TEST_URL=https://127.0.0.1:8766 and PRISM_TLS_TEST_CA=<prism-ca.pem> with the API running on TLS
cd firestore-rules-tests && npm install --ignore-scripts && npm test   # Firestore rules in the emulator
flutter analyze
```

## Results actually obtained

| Suite | Result |
|---|---|
| `ml/tests` (pytest) | **127 passed**, 0 failed (3–6 min; slowest part is fixture training) |
| `test/ml_service_test.dart` + `test/ml_http_client_test.dart` | **13 passed** (incl. 2 live HTTPS tests against the self-hosted API: pinned CA → 200, unpinned → `HandshakeException`) |
| `test/widget_test.dart` (pre-existing) | **fails to load: "Missing definition of main"**. The file is entirely commented out and is unchanged by this work. |
| Firestore rules emulator (`firestore-rules-tests`) | **9 passed** (the first run found a real bug, a missing-claim lookup that denied all app users; fixed with `token.get('prism_device', false)`) |
| `flutter analyze` | 39 issues, all `info` level, **0 errors / 0 warnings** (unmodified code: 42 issues, 0 errors / 0 warnings) |
| Self-hosted TLS (`make_local_tls.sh` + uvicorn TLS) | `openssl verify` OK; OpenSSL-based client with CA → 200; without CA → rejected; plain HTTP → rejected |
| Firebase certificate cache | first verification ≈ 460 ms (fetch), subsequent ≈ 2 ms |
| Live server smoke test (uvicorn, real Firebase verifier) | `/health` 200 with security headers; missing token → 401; invalid token → 401 (verified against Google certs); `/docs` → 404 |
| `node --check functions/index.js` | syntax OK (functions not deployed or run) |
| Real data acquisition | 5 files downloaded; 4 publisher MD5s matched (1 not verifiable, reason recorded) |
| Real training on local data | **not trained**: 0 trusted labels (exit 2), as expected in the calibration phase |

### What the Python tests cover

* **Data quality (21):** missing values/flags, stale and future timestamps, unsynced (1970) clock,
  naive timezone, out-of-range values, NaN, wrong pixel count, firmware 0.0 marker, flat frame,
  fault precedence, water warning non-blocking, calibration mismatch, training mode without freshness.
* **Features (5):** THI against the published formula, contract order/names, thermal summaries,
  determinism and contract hash, water level excluded.
* **Local dataset & splits (14):** fixtures refused for training, label trust rules (confidence, role,
  blinding, protocol, status, window), conflicting labels dropped, quality layer applied at load,
  schema/origin validation, temporal group split disjoint and latest.
* **Training & registry (13):** refuses without enough trusted data; candidate registration with
  contract hash and provenance; **held-out sessions disjoint and counted**; reproducibility (identical
  metrics on rerun); random labels fail acceptance and cannot be approved; fixture-trained model
  refused by a real registry; approve → load → rollback; **tamper detection**; model-id path traversal;
  immutable versions.
* **Inference & insights (33):** no model → Classification Unavailable; **bad data never produces a
  thermal status (and never "Good"), with or without a model**; out-of-range → Uncertain; calibration
  mismatch; contract mismatch disables the model; inference errors contained without leaking internals;
  every reference resolves; THI context only above 84; water sentences; High Risk includes vet advice;
  no diagnostic/medication wording.
* **API (36):** 401 missing/invalid token, lockout after repeated failures, 503 when auth isn't
  configured, valid assessment, stale/missing data states, invalid bodies → 422 without echoing input,
  415, 413, user rate limit, model info, model-load failure, generic 500, **cross-farm access 403**,
  member access, Firestore failure → 503, storage not configured → 503, **device HMAC: valid, bad
  signature, tampered body, replay, old timestamp, unknown device, impersonating another device, body
  device-id mismatch, user token rejected**, mobile contract.
* **CLI (3):** `train.py` exit 2 without labels, `registry.py` list/approve/compare.
* **SQLite store (2):** signed ingestion → latest assessment (timezone-offset ordering), cross-farm 403, member removal, export to loader format.

## ML acceptance criteria

Pre-registered in `ml/configs/acceptance.json` (see ML_PIPELINE.md §6). **No model has been
evaluated against them on real data**, because none exists.

## Not executed / outstanding

* **Hardware end-to-end test (ESP32 → API/Firestore → app): not performed.** The firmware is not in this
  repository; the inspected copy is not the deployed version.
* Real Firebase ID-token acceptance (a *valid* token) and `FirestoreRepository` against a live project:
  not tested (no credentials used). Covered with fakes/in-memory equivalents.
* Firmware HMAC signing, TLS from an actual phone, multi-instance rate limiting: not tested.
* Cloud Functions change: syntax-checked only, not run (Functions need the Blaze plan; see COST_AND_DEPENDENCIES.md).
* Flutter UI changes: analyzer-clean and contract-tested, but **not run on a device**.
* Model validation on farm data: blocked until labelled sessions exist (FARM_DATA_COLLECTION_AND_RETRAINING.md).
