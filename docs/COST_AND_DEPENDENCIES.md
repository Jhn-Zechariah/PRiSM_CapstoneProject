# Cost, dependencies and free-only operation

Verified 2026-10-12 against official sources. **Pricing and policies can change**, so re-check the
linked pages before each deployment. Nothing in this repository enables billing, and no paid service,
API, model provider, dataset or licence was introduced.

## 1. What runs where

| Component | Runs on | Needs internet? | Keeps working if external services fail? |
|---|---|---|---|
| Sensors, sprinkler relay, schedule, safety cut-offs | ESP32 | No (schedule needs NTP once) | **Yes**: local LAN `/sensor` and `/sprinkler` keep working |
| ML pipeline (training, evaluation, registry) | Team computer | Only to download public datasets once | **Yes**, fully offline |
| PRISM API (data quality, model, insights, ingestion) | Self-hosted: team laptop / farm PC / Raspberry Pi | No for LAN clients, except that Firebase token verification needs Google's public signing certificates (fetched over the internet, then cached per their Cache-Control headers) | Yes for device ingestion (HMAC, local SQLite). User endpoints keep working while the cached certificates are valid; after that they need internet. |
| Readings history for training (`sqlite` backend) | Same machine as the API | No | **Yes** |
| Mobile app UI, live LAN readings | Phone | No on the farm LAN | Yes for LAN readings; Firebase-backed features need internet |
| Auth, farm records, global sensor docs, notifications | Firebase (Google) | Yes | No |

The insight sentences come from the project's own code (`prism_ml/insights`). **No LLM or paid AI API
is used anywhere.**

## 2. External services

| Service | Use | Hosting | Cost/plan (official reference) | Card / billing | Risk and mitigation |
|---|---|---|---|---|---|
| Firebase Authentication | app sign-in | Google | Spark: 50K MAU, "No payment method needed"; phone auth not on Spark ([pricing](https://firebase.google.com/pricing)) | none on Spark | Within limits for a capstone. Don't enable phone auth. |
| Cloud Firestore | app records, live sensor docs | Google | Spark: 1 GiB stored, 50K reads/day, 20K writes/day, 20K deletes/day, 10 GiB egress/month ([pricing](https://firebase.google.com/pricing), [quotas](https://firebase.google.com/docs/firestore/quotas)); quotas reset around midnight Pacific; more quota requires enabling billing | none on Spark | **Availability risk** (see §3). On Spark, going over the limit cannot cause charges because no billing account exists. |
| Cloud Functions (`functions/index.js`) | daily stock/expiry/intake reminders, threshold alerts | Google | **Not available on Spark** ("Not applicable"); requires Blaze, which needs a billing account | **billing account required** | **Existing billing dependency.** See §4. Not changed here. |
| Firebase Cloud Messaging | push notifications | Google | "No-cost" | none | Sending requires the Admin SDK (Functions or a self-hosted script). |
| Google/Facebook sign-in | social login in the app | Google / Meta | free login products | none | No change. |
| Zenodo, Recherche Data Gouv, figshare | dataset download | CERN / French gov. / Digital Science | free public access, no account | none | Downloads are checksum-verified. |
| Firebase Emulator Suite (`firestore-rules-tests`) | rules tests | **local** | free, `demo-` project, no login | none | Runs offline after install. |

**Not used and must not be added without explicit approval:** Firebase Blaze plan, Cloud Run, paid
hosting, paid tunnels, paid certificates, paid LLM/AI APIs, paid monitoring.

## 3. Firestore free-quota assessment (current architecture)

Estimated from the deployed firmware (prismoct12) and the app code. Firestore bills each document
`set`/`update` as one write, and each document returned by a query or delivered to a listener as one read
([billing docs](https://firebase.google.com/docs/firestore/pricing)).

| Source | Pattern | ≈ per day |
|---|---|---|
| ESP32 → `live_sensor/latest` | 1 write / 10 s | 8,640 writes |
| ESP32 → `sensor_readings_seconds` | 1 doc per reading (queued readings are sent later, same total) | 8,640 writes |
| ESP32 → `sensor_readings_hourly`, logs, command sync | hourly / per run | < 100 writes |
| App → `sensor_memory/latest` | ≤ 1 write / 60 s while the dashboard is open | up to 1,440 writes per open phone |
| **Writes total** | one phone open all day | **≈ 18,800 of 20,000** |
| ESP32 sprinkler-command poll | 1 read / 15 s | 5,760 reads |
| ESP32 settings fetch | 1 read / 2 min | 720 reads |
| Cloud Function `onLiveSensorUpdate` (Blaze only) | runs on **every** live write and reads the whole `admins` collection | 8,640 × number of admins reads |
| App off the farm LAN | one-shot GET every 10 s + listener updates | up to ≈ 17,000 reads per phone |
| App 24-h charts on `sensor_readings_seconds` | one read per returned document | ≈ 8,640 reads per full-day chart load |

**Conclusion:** writes sit at ≈ 87–95 % of the free 20K/day. Reads can pass 50K/day with two admins
(Cloud Function), one phone off the LAN, and a couple of daily chart loads. The free limits can be exhausted. On Spark this means Firestore stops serving that operation until the daily reset, with no
charge. On Blaze it would be billed. No-cost mitigations, in order:

1. Store per-reading history in the self-hosted API (`PRISM_STORAGE_BACKEND=sqlite`), not in
   Firestore. This is already implemented and is the source for training exports.
2. In firmware, write `live_sensor/latest` only when values change or every 30–60 s, and replace
   `sensor_readings_seconds` with 1-minute (or hourly) aggregates.
3. Make `onLiveSensorUpdate` (if kept) query only admins with alerts enabled, or move alerting to the
   self-hosted API, which reads the reading it just received at zero Firestore cost.
4. Charts: read `sensor_readings_hourly` for ranges over a few hours instead of second-level documents.
5. Keep the project on **Spark** so that exceeding quota cannot cause charges.

## 4. Cloud Functions, Blaze and the 90-day free trial (decision needed)

Verified 2026-10-12 ([Firebase plans](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans),
[Google Cloud free trial](https://docs.cloud.google.com/free/docs/free-cloud-features)):

* Blaze needs a Cloud Billing account, and billing accounts require a payment method. The trial requires
  "a credit card or other payment method".
* Trial: **$300 credit for 90 days**. No charges during the trial, and no automatic charges at the end.
  If you don't upgrade, the billing account closes and "all resources you created during the trial are
  stopped"; Firebase then downgrades the project to Spark and **Cloud Functions stop being deployable**.
* Blaze keeps the same no-cost quotas (Firestore 50K reads / 20K writes per day; Cloud Run functions 2M
  invocations per month). Budget alerts **do not cap** charges.
* The PRISM ML (API, inference, insights, training, SQLite history) uses **no Firestore operations and no
  Blaze service**, so it needs no trial at all.


`functions/` can only be deployed on Blaze. **If those functions are currently deployed, the Firebase
project already has a billing account attached.** This could not be checked: no Firebase console
access was used. Free alternatives, not implemented (the architecture was left unchanged pending your decision):

* **Self-hosted scheduler:** run the three daily checks and the threshold alert as a Python job on the
  same machine as the API (`firebase-admin` reads Firestore and sends FCM; FCM is no-cost). Cost: the
  machine must be on; it needs a service-account key kept on that machine.
* **On-device:** compute low-stock/expiry/intake reminders in the app and show them with
  `flutter_local_notifications` (already a dependency). No server needed, but reminders appear only
  on devices that have opened the app recently.

Recommendation: the self-hosted scheduler for alerts, plus on-device reminders, then downgrade to Spark.

## 5. Free TLS and hosting for the API

`ml/scripts/make_local_tls.sh` (OpenSSL) creates a private CA and server certificate. uvicorn serves
HTTPS natively. The app pins that CA via `--dart-define=PRISM_API_CA_PEM_B64=…`
(`ml_http_client_io.dart`, `SecurityContext(withTrustedRoots: false)`). Verified: the pinned client gets
200; unpinned clients and plain HTTP are rejected (TESTING_AND_VALIDATION.md). Limitation: reachable
only where the phone can reach the server (farm LAN or a VPN you already have). Public internet
exposure would need port forwarding (free, but increases attack surface) or a tunnel service, whose
free tiers were not evaluated or adopted.

## 6. Libraries (all open source, installed locally)

| Library | Version tested | Licence |
|---|---|---|
| fastapi / starlette / pydantic / uvicorn | 0.143.0 / 1.7.0 / 2.14.1 / 0.54.0 | MIT / BSD-3 / MIT / BSD-3 |
| scikit-learn / scipy / numpy / pandas / joblib / threadpoolctl | 1.9.1 / 1.18.1 / 2.5.4 / 3.0.6 / 1.6.0 / 3.7.0 | BSD |
| firebase-admin / google-auth / requests | 7.7.0 / 2.61.0 / 2.34.2 | Apache-2.0 |
| pytest / httpx (dev) | 9.1.1 / 0.28.1 | MIT / BSD-3 |
| firebase-tools / firebase JS / @firebase/rules-unit-testing (rules tests) | 13.35.1 / 10.14.1 / 3.0.4 | MIT / Apache-2.0 / Apache-2.0 |
| Flutter SDK, `http`, Firebase Flutter plugins | as in `pubspec.lock` | BSD-3 / Apache-2.0 |
| OpenSSL (TLS script), SQLite (Python stdlib) | 3.5.6 / bundled | Apache-2.0 / public domain |

Python, Node.js and Eclipse Temurin (Java, for the emulator) are free to use.

## 7. Datasets: training, validation, test

| Dataset | Source / licence | Used for training? | Validation/test? |
|---|---|---|---|
| HotPig | doi:10.5281/zenodo.17090997, CC-BY-4.0 | **No** | No (auxiliary description only) |
| INRAE core BT | doi:10.57745/GPW3E1, Etalab 2.0 | **No** | No (auxiliary description only) |
| Fuzzy-logic RF/RT study tables | doi:10.6084/m9.figshare.7020404, CC-BY-4.0 | **No**: condition means and rules only, no raw observations | No |
| PRISM farm data | own farm | not yet collected | not yet collected |

**Confirmation:** no synthetic data was used to train, validate or test any PRISM model; no PRISM model
has been trained. Synthetic records exist only as software-test fixtures in `ml/tests/fixtures.py`.
They are tagged `synthetic_test_fixture`, are refused by the dataset loader by default, and any model
fitted on them can never be approved or served (enforced and tested). The legacy synthetic datasets
were retired to `legacy/`.
