# Legacy - do not deploy

`prism-ml2.0-synthetic/` is the previous ML service (moved here on 2026-10-12, unchanged except that
`Procfile` was renamed to `Procfile.disabled`). It is kept only for the record.

Why it was retired (details in docs/IMPLEMENTATION_REPORT.md):

* `ml/make_datasets.py` generates **synthetic** rows with NumPy random numbers and labels them with the
  hand-written `farm_label()` / `growth_label()` threshold rules. The Decision Trees therefore re-learn
  those rules; the reported 99.9 % accuracy measures agreement with the rule, not real-world performance.
* The `body_temp` bands (35.5 / 37.0 degC) and THI-level combination are project-defined, not validated.
* Its endpoints (`/predict/farm`, `/predict/pig-growth`) did not match the Flutter client
  (`/api/farm/analyze`, `/api/pig/analyze`).

The replacement lives in `ml/` (see ml/README.md and docs/ML_PIPELINE.md).
