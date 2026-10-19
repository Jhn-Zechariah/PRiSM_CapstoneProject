# Deployment

## 1. Development (local)

```bash
cd ml
python -m venv .venv && .venv/Scripts/activate        # Windows (Linux/macOS: source .venv/bin/activate)
pip install -r requirements-dev.txt                    # exact tested versions: requirements.lock.txt
cp .env.example .env                                   # then edit; never commit .env
set FIREBASE_PROJECT_ID=prism-3cd2c                    # or export on Linux/macOS
uvicorn prism_ml.api.asgi:app --host 127.0.0.1 --port 8000
```

App against a LAN dev server (debug builds only; release requires https):
`flutter run --dart-define=PRISM_API_BASE_URL=http://<laptop-lan-ip>:8000` (bind uvicorn to `0.0.0.0`
for LAN access, only on a trusted network).

## 2. Production API: free, self-hosted (recommended)

No paid hosting, domain, certificate or tunnel is required (see COST_AND_DEPENDENCIES.md).

1. Use an always-on machine on the farm network (old laptop, mini-PC or Raspberry Pi 4/5 running
   Linux or Windows) with a fixed LAN IP (DHCP reservation on the router).
2. Install Python and `pip install -r requirements.txt` (versions as in `requirements.lock.txt`, which
   must match the model's `metadata.json`).
3. TLS: `sh scripts/make_local_tls.sh <server-lan-ip>` → `secrets/tls/` (git-ignored). Keep
   `prism-ca.key` offline (USB drive) after generating; only `server.key`/`server.pem` stay on the server.
4. Environment (`.env` or OS service config, never committed): `PRISM_ENV=production`,
   `FIREBASE_PROJECT_ID`, `PRISM_STORAGE_BACKEND=sqlite`, `PRISM_DEVICE_SECRETS_JSON`.
5. Run (systemd service / Windows Task Scheduler "at startup"):
   `uvicorn prism_ml.api.asgi:app --host 0.0.0.0 --port 8443 --ssl-keyfile secrets/tls/server.key --ssl-certfile secrets/tls/server.pem --no-access-log`
6. Farm membership: `python scripts/farms.py add-member <farmId> <firebaseUid>`.
7. Backups (free): copy `data/local_store/prism.sqlite3` (use `sqlite3 prism.sqlite3 ".backup b.sqlite3"`
   while running) and `artifacts/` daily to a second disk/USB; keep 30 days.
8. Updates: `git pull`, `pip install -r requirements.txt`, `pytest`, restart the service.
9. Firewall: allow inbound 8443 from the LAN only; do not port-forward from the internet.

Hosted alternatives (Cloud Run, paid VMs, tunnels) were **not** adopted; any of them needs fresh
verification of current free-tier terms and explicit approval before use.

## 3. Model artifacts

* `ml/artifacts/` (or `PRISM_ARTIFACTS_DIR`) holds `registry.json` and `models/<id>/`. Ship it with the
  deployment (mounted volume or bucket synced at start-up), read-only for the API process.
* Promote: `python scripts/export_readings.py --farm <id>` (+ reviewer labels) → `python scripts/train.py` → `python scripts/registry.py compare <id>` → `python
  scripts/registry.py approve <id> --by "Name, role"` → restart the API.
* Roll back: `python scripts/registry.py rollback --by "Name, role" --note "reason"` → restart.
* Back up `artifacts/` after every approval; `registry.json` is the audit trail.

## 4. Firebase

1. Fix `.firebaserc` default to `prism-3cd2c` (currently `prism-capstone-svncte`).
2. Device identity (prerequisite for the rules):
   ```python
   # one-off admin script, run with an admin service account (never on the device)
   from firebase_admin import auth, initialize_app; initialize_app()
   u = auth.create_user(email="esp32-pen-1@devices.invalid", password="<random>")
   auth.set_custom_user_claims(u.uid, {"prism_device": True})
   ```
   Firmware: `POST https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=<WEB_API_KEY>`
   → `idToken` (refresh before expiry via `securetoken.googleapis.com/v1/token`), and add
   `Authorization: Bearer <idToken>` to every Firestore REST call. Validate TLS (load Google's root CA;
   remove `setInsecure()`).
3. Deploy the rules: add `"firestore": {"rules": "firestore.rules"}` to `firebase.json`, run
   `cd firestore-rules-tests && npm test`, then `firebase deploy --only firestore:rules`.
4. Only if `PRISM_STORAGE_BACKEND=firestore`: create `farms/{farmId}` documents with `memberUids`
   (counts against the Spark write quota; the `sqlite` backend avoids this).
5. Cloud Functions require the paid-capable **Blaze** plan. Do not deploy them on a free-only project;
   see COST_AND_DEPENDENCIES.md §4 for free alternatives.

## 5. Firmware changes required for feature contract v1 (not implemented here)

The firmware is not in this repository, so these changes were **not made or tested**:

* Already done in the deployed firmware (prismoct12): DHT22 temperature → `ambientTemp`/`ambientTempValid`
  (the app maps it to `air_temp_c`), `thermalPixels` + `thermalValid`, `ambientHumidity` + `ambientHumidityValid`,
  `timestamp` (UTC ISO-8601).
* Add `calibrationProfile` once calibration offsets are fixed.
* For training data, each stored reading needs the full 64-pixel frame. `sensor_readings_seconds` has
  none. Prefer the signed ingestion endpoint (self-hosted SQLite, no Firestore quota). If Firestore must be
  used, add `thermalPixels` to a history document only every 60 s: no extra writes per document, but each
  document grows to ≈1–1.5 KB.
* Set `waterValid=false` when the ultrasonic sensor returns no echo (today it reports "Empty").
* To build training data, POST each reading to `/v1/devices/{id}/readings`, signing with HMAC-SHA256
  (`mbedtls_md_hmac` on ESP32) using the string defined in API_REFERENCE.md and an NTP-synchronised
  timestamp. Store the secret in NVS, not in source.

## 6. Mobile app

```bash
flutter build apk --release   --dart-define=PRISM_API_BASE_URL=https://<server-lan-ip>:8443   $(cat ml/secrets/tls/dart_define.txt)        # pins the project's own CA (public certificate)
```
Use a release keystore (SECURITY.md open issue 4). Without the CA flag the app uses the normal system
trust store (for an API with a publicly trusted certificate).
