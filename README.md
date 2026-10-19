# PRISM: IoT-Based Smart Swine Temperature Monitoring and Management System

Flutter/Firebase mobile app, ESP32 sensor node (AMG8833 thermal array, DHT22, HC-SR04, sprinkler
relay), and a Python ML service that classifies the **current** thermal status of a pen as Good / Needs
Attention / High Risk and returns sentence-based guidance.

> **ML status:** no classifier is deployed yet. The sensors are being calibrated, so there are no
> genuine labelled farm data, and no public dataset matches PRISM's sensors (see
> [docs/DATASETS_AND_PROVENANCE.md](docs/DATASETS_AND_PROVENANCE.md)). The app shows
> *Classification Unavailable* plus measurement-based guidance until a model passes the acceptance
> criteria on reviewer-labelled farm data.

## Repository layout

| Path | Contents |
|---|---|
| `lib/` | Flutter app (`lib/core/services/ml_service.dart` = API client) |
| `ml/` | ML pipeline, insights and FastAPI service ([ml/README.md](ml/README.md)) |
| `functions/` | Firebase Cloud Functions (stock/expiry/intake reminders, sensor threshold alerts) |
| `firestore.rules`, `firestore-rules-tests/` | Target Firestore security rules + emulator tests (not yet deployed; see docs/SECURITY.md) |
| `docs/` | Technical documentation |
| `legacy/` | Retired synthetic-data ML service (do not deploy) |

## Prerequisites

Flutter 3.41 / Dart 3.11, Python 3.11+ (tested on 3.14.5), Node 22 + Java 11+ (rules tests only), and
Firebase project `prism-3cd2c`.

## Quick start

```bash
# ML service
cd ml && python -m venv .venv && .venv/Scripts/activate && pip install -r requirements-dev.txt
pytest
set FIREBASE_PROJECT_ID=prism-3cd2c && uvicorn prism_ml.api.asgi:app --port 8000

# Mobile app (API URL injected at build time; release builds require https)
flutter pub get
flutter test test/ml_service_test.dart
flutter run --dart-define=PRISM_API_BASE_URL=http://<lan-ip>:8000      # debug only

# Firestore rules (emulator)
cd firestore-rules-tests && npm install --ignore-scripts && npm test
```

## Documentation

* [Audit report](docs/AUDIT_REPORT.md) (state before this work)
* [ML pipeline](docs/ML_PIPELINE.md) · [Model card](docs/MODEL_CARD.md) · [Datasets & provenance](docs/DATASETS_AND_PROVENANCE.md)
* [Actionable insights](docs/ACTIONABLE_INSIGHTS.md) · [API reference](docs/API_REFERENCE.md)
* [Security](docs/SECURITY.md) · [Deployment](docs/DEPLOYMENT.md) · [Testing & validation](docs/TESTING_AND_VALIDATION.md)
* [Farm data collection & retraining](docs/FARM_DATA_COLLECTION_AND_RETRAINING.md) · [Sensor thresholds & sources](docs/SENSOR_THRESHOLDS.md)
* [Cost, free-tier limits & dependencies](docs/COST_AND_DEPENDENCIES.md)
* [Implementation report](docs/IMPLEMENTATION_REPORT.md)
