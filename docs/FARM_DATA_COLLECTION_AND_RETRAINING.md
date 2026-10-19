# Farm data collection, labelling and retraining (protocol PRISM-LABEL-1.0, draft)

This is the only route to an approved classifier. **Draft:** have the adviser and a veterinarian or
agricultural expert review and sign it before collecting labels. Record their names in the protocol log.

## 0. Prerequisites (calibration phase: current)

1. Finish sensor calibration (paper objective 2). For each device record: date, reference instruments
   (e.g. calibrated thermometer/hygrometer; a contact or IR reference for the AMG8833), offsets applied,
   mounting height, angle and distance to the pigs. Give each setup a **calibration profile id** (e.g.
   `pen1-2026-11-v1`) and have the firmware send it as `calibrationProfile`.
2. Do not collect training data while offsets or mounting are still changing. A model is only valid for
   the profiles it was trained on (enforced by the API).
3. Update the firmware (DEPLOYMENT.md §5) so each reading includes air temperature, humidity, the full
   thermal frame and validity flags, and is stored in `farms/{farmId}/sensor_readings`.
4. Data protection: farm data stay in the project's Firebase project; exports live only in
   `ml/data/raw/local/` on team machines (git-ignored). No names or locations go in labels beyond the ids
   needed. Delete exports when the project ends unless the farm owner agrees otherwise.

## 1. Sensor validation before each collection day

* Device online and NTP-synchronised (timestamps ≠ 1970); readings arrive every ~10 s.
* DHT22 within ±1 °C / ±5 % RH of the reference instrument, checked at the pen.
* AMG8833 lens clean and unobstructed; the frame shows the pigs (not uniform); no `Sensor Check Required`.
* Record any problem in the session log. Readings from a failed check are kept but not labelled.

## 2. Label sessions

A **label session** is one reviewer's assessment of one pen over **5–15 minutes** (≤ 30 min accepted).

1. The reviewer must be a veterinarian, an agricultural expert, or a *trained observer* who passed
   the agreement check (§6).
2. **Blinding:** the reviewer must not see the PRISM app, the sensor values or the current status
   during the session (`reviewer_blinded=true`). Otherwise the label is untrusted.
3. Observe the pigs and record the evidence:
   * resting respiration rate: count flank movements for 30 s ×2 (`respiration_rate_bpm`);
   * panting / open-mouth breathing (yes/no); lying apart or lateral lying (yes/no); wallowing or pen
     fouling (yes/no); activity when approached;
   * optional, by a veterinarian only: rectal temperature (`rectal_temp_c`).
4. Assign the status using the definitions in ML_PIPELINE.md §1, based on the animals and not on
   thermometers. Set `label_confidence` to `confirmed` only if the reviewer is sure; otherwise use
   `probable`/`uncertain` (kept, but never used for training).
5. Write one row in `ml/data/raw/local/labels/<date>_<reviewer>.csv` (template:
   `ml/templates/label_sessions_template.csv`) with UTC `window_start`/`window_end`, `farm_id`,
   `pen_id` (= device id), `protocol_version=PRISM-LABEL-1.0`.
6. Spread sessions across times of day (including the hot afternoon reported in the paper's survey),
   days and weather. Collect all three classes. **Never induce heat stress to obtain High Risk
   labels.** Record naturally occurring conditions only, and act on the pigs' welfare first.

Target before the first training attempt (configs/acceptance.json): ≥ 20 sessions, ≥ 4 per class,
≥ 600 labelled readings. Realistically plan for 40+ sessions, since High Risk is rare.

## 3. Export and assemble

```bash
cd ml
python scripts/export_readings.py --farm <farmId>     # self-hosted SQLite store → data/raw/local/readings/
# put reviewer CSVs in data/raw/local/labels/
python scripts/train.py
```

Raw exports are never edited. Corrections go in a new label file with a new `label_session_id`; the old
row is marked `probable`/`uncertain`.

## 4. Training, comparison, approval

1. `python scripts/train.py` registers an immutable **candidate**: exit code 0 if it passed acceptance,
   1 if it failed, 2 if the data are insufficient. Read `reports/training_<id>.json`.
2. `python scripts/registry.py compare <id>` shows it next to the approved model. Because test sets
   differ between runs, also evaluate the current model on the newest sessions before replacing it.
3. Approval requires: acceptance passed, the adviser and an expert reviewed the confusion matrix
   (especially High Risk misses), and the model card was updated from `evaluation.json`.
   `python scripts/registry.py approve <id> --by "Name, role" --note "…"`. Restart the API.
4. Rollback: `python scripts/registry.py rollback --by "Name, role" --note "reason"`, then restart.

## 5. Ongoing monitoring

* Monthly: share of readings with data-quality issues; share of `Uncertain`; feature distributions vs
  `validated_feature_ranges`.
* Keep running blinded label sessions (e.g. 2/week). Compare the model's status with the reviewer's
  label to track live accuracy, and retrain when it drops or the calibration profile changes.
* **No automatic retraining.** Unreviewed incoming readings never become labels.
* **No pseudo-labelling:** the model's own predictions are never used as labels. The loader accepts
  labels only from reviewer label-session files, which reviewers fill in blinded to PRISM's output.

## 6. Inter-rater agreement

Before a trained observer's labels are trusted, they and a veterinarian label ≥ 10 sessions
independently. Report Cohen's κ. If κ < 0.6, retrain the observer and repeat.
