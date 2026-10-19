# ML pipeline

Code: `ml/prism_ml/`. Configuration: `ml/configs/`. Commands run from `ml/` with the venv active.

```
ESP32 reading ─► data-quality layer ─► feature contract v1 ─► approved model ─► abstention ─► insights
                 (prism_ml.data.quality) (prism_ml.features)   (registry)        (validated)   (prism_ml.insights)
```

## 1. Task definition

**Current thermal-status classification.** Given one recent, valid reading, classify the *currently
observed* condition of the monitored pen as **Good**, **Needs Attention** or **High Risk**. The pipeline
has no forecasting: no future readings, no hours-ahead risk.

Label definitions (operational, set by a qualified reviewer observing the pigs, *not* from sensor values):

| Class | Reviewer's assessment of the pigs during the session |
|---|---|
| Good | No animal-based heat-stress signs; behaviour normal for the time of day |
| Needs Attention | Early signs: raised resting respiration, pigs seeking cool/wet spots, lying apart, reduced activity |
| High Risk | Marked signs: panting/open-mouth breathing, respiration well above 50/min at rest, lethargy, pen fouling from wallowing, any pig not rising |

Indicators follow Vermeer & Aarnink (2023). The full protocol, including blinding and evidence
fields, is in FARM_DATA_COLLECTION_AND_RETRAINING.md. These definitions are **proposed** and need sign-off
by the adviser and a veterinarian/agricultural expert before labelling starts.

## 2. Data

* External data: acquired and audited but **not usable for training** (DATASETS_AND_PROVENANCE.md).
* Local data: `data/raw/local/readings/*.csv` plus `data/raw/local/labels/*.csv`
  (`prism_ml.data.local_dataset`). A reading is labelled only if it lies inside exactly one **trusted**
  label session for the same farm and pen. Trusted means: confirmed confidence, an accepted reviewer
  role, the reviewer blinded to PRISM output, protocol `PRISM-LABEL-1.0`, and a window of at most
  30 min. Untrusted sessions are kept apart for review. Conflicting or overlapping labels are dropped
  and counted.
* `data_origin` must be `farm`. Rows marked `synthetic_test_fixture` are refused (and a model trained on
  them can never be approved or served).
* Preprocessing: duplicate `reading_id`s dropped; timestamps parsed to UTC; then the **same
  data-quality rules as inference** (freshness excluded). Readings that would be rejected live never
  enter training. Extreme but valid heat readings are kept; only physically impossible or
  device-flagged values are removed, and each removal is counted in the dataset summary.

## 3. Data-quality layer (`configs/data_quality.json`)

Explicit integrity rules, kept separate from the classifier. Outputs are only operational states.

| Check | Result |
|---|---|
| Missing value / missing validity flag / missing or naive timestamp | Insufficient Data |
| Reading older than 120 s | Insufficient Data |
| Device flag invalid, value outside sensor range (DHT22 −40–80 °C, 0–100 %; AMG8833 0–80 °C), NaN | Sensor Check Required |
| Thermal frame ≠ 64 pixels, any pixel exactly 0.0 (firmware's invalid marker), flat frame (σ < 0.05 °C) | Sensor Check Required |
| Clock not synchronised (year < 2024), timestamp > 60 s in the future | Sensor Check Required |
| Calibration profile differs from the model's training profiles | Sensor Check Required |
| Water sensor invalid | informational only (never blocks) |

## 4. Feature contract v1 (`configs/feature_contract_v1.json`)

`air_temp_c`, `relative_humidity_pct`, `thi` (Vermeer & Aarnink formula), `thermal_max_c`,
`thermal_top4_mean_c`, `thermal_median_c`, `thermal_std_c`, `thermal_hot_minus_air_c`. A single
function (`build_features`) serves training and inference. The contract's SHA-256 is stored with each
model, and the API refuses a model whose hash differs. Excluded: core body temperature (not measured),
water level (not a thermal-state signal), feed/weight (not linked to readings).

## 5. Training (`prism_ml.models.train`, `scripts/train.py`)

1. Check data requirements (`configs/acceptance.json`): ≥ 600 trusted readings, ≥ 20 sessions, ≥ 4
   sessions per class. If unmet, **nothing is trained** (exit code 2) and a report is written.
2. **Temporal group hold-out:** the latest 25 % of label sessions form the test set. Sessions never
   span train and test (asserted).
3. Model selection by `StratifiedGroupKFold` (4 folds, grouped by session) on training sessions only.
   Candidates: Decision Tree (the paper's algorithm and baseline), Random Forest,
   HistGradientBoosting, all with `class_weight="balanced"`. Grids in `configs/training.json`. Selection
   uses CV macro-F1, never the test set.
4. Sigmoid probability calibration (grouped inner CV).
5. **Abstention threshold** from out-of-fold validation probabilities: the smallest threshold whose
   accepted predictions reach macro-F1 ≥ 0.80 with coverage ≥ 60 %. If none qualifies, the model fails
   acceptance.
6. One evaluation on the held-out test set: macro-F1, balanced accuracy, per-class precision/recall,
   confusion matrix, High Risk recall/FNR, "Good shown for High Risk" rate, multiclass Brier score,
   abstention coverage, majority-class baseline, and per-farm macro-F1.
7. Acceptance decision against the pre-registered criteria, then registration as an immutable
   **candidate** (`artifacts/models/<id>/` with SHA-256s). Approval is a separate manual step.

Fixed seed `20261012`; library versions and the config snapshot are stored in the model metadata.

## 6. Acceptance criteria (pre-registered 2026-10-12, `configs/acceptance.json`, status: proposed)

High Risk recall ≥ 0.90 (FNR ≤ 0.10); macro-F1 ≥ 0.70; balanced accuracy ≥ 0.70; Needs Attention
recall ≥ 0.60; Good shown for High Risk ≤ 2 %; macro-F1 at least 0.15 above the majority baseline;
Brier ≤ 0.45; ≥ 5 test sessions and ≥ 20 test readings per class; a valid abstention threshold.

## 7. Inference (`prism_ml.models.inference`)

Order: quality gate → approved model present? → calibration profile → inside the training feature
ranges? → calibrated probabilities → below the abstention threshold ⇒ **Uncertain** → otherwise the
class. Any model-loading failure, contract mismatch or inference exception yields **Classification
Unavailable** (logged server-side, never shown in detail to the client).

## 8. Current state (2026-10-12)

`python scripts/train.py` → `NOT TRAINED – 0 trusted labeled readings < required 600 …` (exit 2).
The registry is empty (`approved: null`), so the API returns *Classification Unavailable* plus
measurement-based guidance. This is the intended behaviour until genuine labelled farm data exist.

## 8a. Initial-model decision

The team chose to train the first model on its own reviewer-labelled farm data (2026-10-12). No external
dataset is used for training, validation or testing (DATASETS_AND_PROVENANCE.md).

## 9. Retraining

See FARM_DATA_COLLECTION_AND_RETRAINING.md. Retraining is always manual: new readings never become
labels automatically, there is no automatic retraining, and every candidate is compared with the
approved model before approval.
