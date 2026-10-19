# PRISM ML (`ml/`)

Current thermal-status classification pipeline (Good / Needs Attention / High Risk), data-quality layer,
evidence-based insights and the FastAPI service. Full documentation: [`../docs/`](../docs/).

**State (2026-10-12):** no approved model. There are no genuine labelled farm data yet (sensor
calibration phase), and no external dataset is compatible. The API therefore returns
`Classification Unavailable` with measurement-based guidance.

```bash
python -m venv .venv && .venv/Scripts/activate      # Windows; Linux/macOS: source .venv/bin/activate
pip install -r requirements-dev.txt

python scripts/acquire_external.py    # download + checksum-verify HotPig and INRAE (≈190 MB)
python scripts/audit_external.py      # feasibility audit -> data/metadata/external_audit.json
python scripts/export_readings.py --farm <farmId>   # local readings from the self-hosted SQLite store
python scripts/farms.py add-member <farmId> <uid>   # farm membership (sqlite backend)
sh scripts/make_local_tls.sh <server-lan-ip>        # free self-hosted TLS (own CA)
python scripts/train.py               # trains only with enough trusted labels (exit 2 otherwise)
python scripts/registry.py list|compare|approve|rollback

pytest                                # full suite
uvicorn prism_ml.api.asgi:app --host 127.0.0.1 --port 8000   # needs FIREBASE_PROJECT_ID
```

| Path | Purpose |
|---|---|
| `configs/` | feature contract, data-quality rules, training config, pre-registered acceptance criteria, dataset registry |
| `prism_ml/data/` | acquisition, external audit, data-quality layer, local dataset + label trust, splits |
| `prism_ml/features/` | feature contract v1 (shared by training and inference) |
| `prism_ml/models/` | training, evaluation, registry (integrity, approval, rollback), inference |
| `prism_ml/insights/` | sentence-based guidance + references |
| `prism_ml/api/` | FastAPI app, auth (Firebase ID token, device HMAC), security middleware, storage |
| `templates/` | CSV templates for readings and reviewer label sessions |
| `tests/` | unit, ML, API, security, contract and CLI tests (`tests/fixtures.py` = synthetic **test fixtures only**) |
