# Security

Status legend: **Implemented + tested**, **Implemented, needs deployment config**, **Open**.

## Architecture and trust boundaries

```
ESP32 ──(HTTPS, HMAC-signed)──► PRISM API ──(service account)──► Firestore farms/{id}/sensor_readings
  │                                ▲
  └──(today: unauthenticated REST + web API key)──► Firestore live_sensor/... ◄── Flutter app (Firebase Auth)
                                   └──(HTTPS, Firebase ID token)── Flutter app
```

Secrets: per-device HMAC secrets (device flash + server secret store); the API's service-account key
(server only). Nothing confidential belongs in the Flutter app, the firmware repository, or Firestore.

## Controls

| Control | Status | Where |
|---|---|---|
| User auth: Firebase ID token verified (signature, `aud`, `iss`, `exp`, `sub`) | Implemented + tested (fake verifier in tests; real verifier smoke-tested to reject an invalid token) | `prism_ml/api/auth.py` |
| Device auth: HMAC-SHA256 over timestamp, nonce, method, path and body hash; ±300 s skew; nonce replay cache; constant-time compare | Implemented + tested | `auth.py`, `security.py` |
| Device bound to its own farm; path/body device id must match | Implemented + tested | `main.py` |
| Farm authorization (`memberUids`) for stored readings | Implemented + tested (in-memory repo) | `main.py`, `repository.py` |
| Explicit schemas (`extra=forbid`, finite numbers, ≤ 64 pixels, id patterns) | Implemented + tested | `schemas.py` |
| Body limit 16 KB (Content-Length and streamed), JSON content type only | Implemented + tested | `security.py` |
| Rate limits (user 30/min, device 20/min) and lockout after 10 auth failures / 5 min, with warning log | Implemented + tested (per process only) | `security.py` |
| Safe errors: generic messages + request id; no stack traces or input echo | Implemented + tested | `main.py` |
| Security headers (nosniff, no-store, DENY frames, no-referrer; HSTS in production) | Implemented + tested | `security.py` |
| CORS off by default; wildcard rejected | Implemented | `settings.py` |
| `/docs` and OpenAPI disabled unless `PRISM_ENABLE_DOCS=true` outside production | Implemented + tested | `main.py` |
| Logs pseudonymise user/device ids; no readings in logs | Implemented | `security.pseudonym` |
| Upstream timeouts (Firestore 5 s) → 503 | Implemented + tested (simulated failure) | `repository.py` |
| Model integrity: SHA-256 per artifact; only registry-listed files loaded; path-traversal-safe ids; no upload endpoint; fixture-trained models refused | Implemented + tested | `models/registry.py` |
| Dataset integrity: publisher MD5 verified, SHA-256 provenance | Implemented + run | `data/acquire.py` |
| Firestore rules: owner-only farm records, device-only sensor writes, validated sprinkler command, member-only farm data, default deny | Written + **emulator-tested (9/9)**, **not deployed** | `firestore.rules`, `firestore-rules-tests/` |
| App: no secrets, https enforced in release, friendly errors, no placeholder inputs | Implemented + tested | `ml_service.dart` |
| TLS for the self-hosted API (own CA via OpenSSL; uvicorn TLS; app pins the CA) | Implemented + tested live (pinned client 200; unpinned and plain HTTP rejected) | `ml/scripts/make_local_tls.sh`, `lib/core/services/ml_http_client_io.dart` |
| Self-hosted storage (SQLite) with farm membership; readings never leave the farm machine | Implemented + tested | `repository.SQLiteRepository`, `scripts/farms.py` |

## Firestore rules: deployment prerequisite

`firestore.rules` denies all unauthenticated access. **The current firmware is unauthenticated**, so
deploying the rules as they stand stops it from working. Migrate first (DEPLOYMENT.md "Device identity"):

1. Create a Firebase Auth user per device and set the custom claim `prism_device: true` with the Admin
   SDK. The firmware signs in via the Identity Toolkit REST API and sends `Authorization: Bearer
   <idToken>` on Firestore REST calls; **or**
2. post readings to `POST /v1/devices/{id}/readings` with an HMAC secret, and read sprinkler commands
   with the device identity from option 1.

Then add `"firestore": {"rules": "firestore.rules"}` to `firebase.json`, fix `.firebaserc` to the real
project (`prism-3cd2c`; it currently says `prism-capstone-svncte`), and deploy.

## Open issues (not fixed here)

1. **Firmware is unauthenticated and uses `setInsecure()`** (no TLS certificate validation). It must
   pin or validate Google's root CA and use a device identity. The firmware is not in this repository and
   was not modified or tested.
2. **Wi-Fi credentials in firmware source.** Keep the source out of public repos; if it was ever shared,
   change the Wi-Fi password. Move credentials to provisioning (WiFiManager/NVS).
3. **Firebase API keys** (`google-services.json`, `firebase_options.dart`) are public identifiers, but
   restrict them in Google Cloud Console (Android app restriction with package name + SHA-1; API
   allow-list). Removing them from the latest commit would not remove them from Git history, and it
   isn't needed: their safety comes from restrictions plus rules, not secrecy.
4. **Release signing uses the debug keystore** (`android/app/build.gradle.kts`). Create a release
   keystore kept outside the repo and configure it via `key.properties`.
5. Single-farm Firestore schema: every signed-in user can read the global sensor collections, and
   `onLiveSensorUpdate` alerts every admin. Real multi-farm isolation needs the `farms/{farmId}` layout.
6. Rate limiting and the nonce cache are in memory; with more than one API instance, add a shared store
   or a gateway limit.
7. uvicorn's access log records client IPs; run with `--no-access-log` behind a proxy that applies your
   retention policy.
8. Not tested: real Firebase token verification with a valid token, Firestore repository against a real
   project, firmware HMAC signing, TLS on a phone (tested from the Dart VM on the development PC).
9. Security does not depend on any paid service. The trade-off of free self-hosting: the API is reachable
   only on the farm LAN (or an existing VPN), and the team is responsible for patching, backups and
   physical security of the server.

## Key rotation and incident response

* **Device secret leaked / device lost:** generate a new secret
  (`python -c "import secrets; print(secrets.token_urlsafe(32))"`), update `PRISM_DEVICE_SECRETS_JSON`
  and the device, restart the API. Remove the old entry to revoke immediately. Review stored readings
  from that device since the suspected leak (`deviceId`, `receivedAt`).
* **Service-account key leaked:** disable/delete the key in IAM, create a new one (or use workload
  identity), and check Cloud Audit Logs for its use.
* **Firebase user compromise:** disable the user in Firebase Auth and revoke refresh tokens
  (`auth.revoke_refresh_tokens(uid)`).
* **CA key leaked:** run `make_local_tls.sh` in a new directory (new CA), rebuild the app with the new
  `dart_define.txt`, replace the server certificate, and uninstall old app builds.
* **Model artifact tampering:** the API refuses to load it (integrity failure → Classification
  Unavailable). Restore the artifact from backup or `scripts/registry.py rollback`.
* **Suspicious traffic:** search logs for `auth_failures_threshold`; block the source at the proxy/firewall.
* After any incident: record what happened, rotate affected secrets, and add a test if a control failed.
