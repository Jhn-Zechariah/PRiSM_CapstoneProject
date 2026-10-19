# Model card: PRISM current thermal-status classifier

| | |
|---|---|
| **Approved model** | **None.** Registry `approved: null` (2026-10-12) |
| Reason | No genuine, reviewer-labelled PRISM farm data exist; the sensors are being calibrated and Firestore holds no clean data. No external dataset is compatible (DATASETS_AND_PROVENANCE.md). |
| Behaviour without a model | API returns `Classification Unavailable` with measurement-based, referenced guidance; it never shows Good / Needs Attention / High Risk. |
| Pipeline status | Implemented and tested end to end on clearly labelled synthetic *test fixtures* only. Those runs are software tests, not evidence of performance. |

This card describes the model that the pipeline will produce. Sections marked **TBD** must be filled
from `artifacts/models/<id>/evaluation.json` when a candidate is approved. Do not fill them by hand.

## Intended use

* Classify the **current** thermal status of one small pen (2–4 pigs, the paper's scope) monitored by
  one ESP32 with an AMG8833 and a DHT22, as Good / Needs Attention / High Risk, to prompt the farmer
  to look at the pigs and act.
* Decision support for small-scale farms. The farmer decides whether to run the sprinkler (paper 1.2.4).

## Prohibited / out-of-scope uses

* Diagnosing disease, fever, heat stroke, or whether an individual pig is healthy or sick.
* Forecasting future temperature or heat stress.
* Replacing veterinary assessment, or justifying the withholding of veterinary care.
* Automatically actuating the sprinkler or other equipment.
* Farms, pens, devices or calibration profiles not represented in the training data. These receive
  `Uncertain` or `Sensor Check Required`.
* Individual pig weight/growth classification (no validated growth model exists).

## Inputs

Feature contract v1 (`configs/feature_contract_v1.json`): DHT22 air temperature and RH, THI, and
AMG8833 frame summaries (max, top-4 mean, median, std, top-4 minus air). The AMG8833 measures
*apparent surface temperature* (±2.5 °C); the model never treats it as core temperature.

## Training data

**TBD.** Required: ≥ 600 trusted labelled readings in ≥ 20 blinded reviewer label sessions, ≥ 4 per class,
protocol PRISM-LABEL-1.0. Record farm(s), dates, season, pig stage, calibration profile and reviewer roles.

## Algorithm and procedure

Best of Decision Tree / Random Forest / HistGradientBoosting by grouped CV macro-F1, with
class-balanced weights, sigmoid calibration and an abstention threshold chosen on out-of-fold
predictions (ML_PIPELINE.md §5). **Selected algorithm: TBD.**

## Evaluation (held-out temporal test sessions)

**TBD** (macro-F1, balanced accuracy, per-class precision/recall, confusion matrix, High Risk
recall/FNR, Good-for-High-Risk rate, Brier, coverage, majority baseline, per-farm results).
Acceptance criteria are fixed in `configs/acceptance.json` (proposed 2026-10-12).

## Uncertainty handling

* Data-quality gate before the model (missing, stale, invalid, flat frame, unsynced clock, calibration mismatch).
* Inputs outside the min–max range of the training features → `Uncertain`.
* Maximum calibrated probability below the validated threshold → `Uncertain`.
* Confidence is shown with every thermal status.

## Known limitations and risks

* Labels from human observation are subjective. Inter-rater agreement must be measured (protocol §6).
* A single farm/pen means results may not transfer to other housing, breeds, seasons or sensor
  mounting positions (distance and angle change AMG8833 readings).
* The 8×8 array sees pigs, floor and walls together; a hot floor or sunlit wall can dominate `thermal_max_c`.
* Consecutive readings are highly correlated; the effective sample size is the number of sessions,
  not readings.
* Firmware/calibration changes alter the input distribution, so a model must be retrained per
  calibration profile.

## Do not trust the model when

* Any data-quality warning is present, or the reading is older than 2 minutes.
* The device, its position, or the calibration profile changed after training.
* Pigs show signs of distress regardless of the displayed status. Observe the animals first.
