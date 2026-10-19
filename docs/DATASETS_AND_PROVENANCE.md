# Datasets and provenance

**Bottom line:** no dataset currently used for training. Two genuine external datasets were downloaded,
checksum-verified and audited. Neither contains PRISM's inputs (AMG8833 thermal frame, DHT22 air
temperature and humidity) together with defensible current-thermal-status labels, so both are
**excluded from the classifier**. They are used only for descriptive auxiliary analysis. The project is in
the sensor-calibration phase and Firestore holds no clean farm data, so no local dataset exists yet.

| Dataset | Inspected | Downloaded | Processed | Used for training | Status |
|---|---|---|---|---|---|
| HotPig (Zenodo 17090997) | yes | yes (series.zip, metadata.txt) | audited | **no** | excluded, auxiliary only |
| INRAE core body temperature (doi:10.57745/GPW3E1) | yes | yes (raw, metadata, docx) | audited | **no** | excluded, auxiliary only |
| Environmental pig barn dataset (Zenodo 17853650) | metadata only | no | no | no | excluded: CO₂/NH₃/ambient only, no animal data |
| LPS saliva inflammation (Zenodo 18955503) | metadata only | no | no | no | excluded: unrelated task |
| TIRPigEar thermal ear images | literature only | no | no | no | excluded: segmentation masks, no status labels |
| Fuzzy-logic RF/RT study (figshare 7020404) | metadata + article tables | tables only (served empty) | no | no | excluded: **condition means only, no raw data**; inputs (air temp + IR surface temp) match PRISM, so ask the authors for raw data |
| PRISM farm data (Firestore) | schema only | no | no | no | **does not exist yet** (calibration phase) |
| `prism-ml2.0` synthetic CSVs | yes | n/a | n/a | no | retired to `legacy/` (synthetic, rule-labelled) |

Reproduce: `python ml/scripts/acquire_external.py` then `python ml/scripts/audit_external.py`. All
numbers below come from `ml/data/metadata/external_audit.json`. Raw files sit unchanged in
`ml/data/raw/external/` (git-ignored; redistribution is allowed by both licences with attribution, but
the 185 MB file is not committed). SHA-256 values are in `ml/data/metadata/provenance.json`.

## 1. HotPig: a behavioural dataset of pigs under heat stress

* **Authors:** Bonneau de Beaufort L., Xavier C., Renaudeau D., Largouët C., Gondret F. (INRAE)
* **DOI:** 10.5281/zenodo.17090997, published 2025-09-10. **Licence:** CC-BY-4.0
* **Files used:** `series.zip` (MD5 `ecd7562d…` verified, SHA-256 `1ba51251…`), `metadata.txt`
  (MD5 verified). Not downloaded: `frames.zip` (621 MB YOLO images), `demo.mp4` (4.2 GB), `weights.zip`.
* **Setting:** 24 individually housed growing pigs, video-monitored. 9 days thermoneutral (22 °C),
  6 days heat stress (32 °C), 1 day back; temperature transitions coded TU/TD.
* **Contents:** 24 CSV files, 552,960 rows (1-minute sampling), 2024-09-30 to 2024-10-30. Columns:
  `datetime, period, conditions, feed, unknown, standing, seating, lying, eating, drinking, cuddling,
  curious, idle, drink, eat, mate, state`. Behaviour columns are counts of frames (of 150 per minute)
  from a YOLOv11 detector. 2,142 rows have missing values (recording gaps). No duplicate timestamps.
* **Labels:** the only target-like column is the experimental condition (TN/HS/TU/TD), a property
  of the room schedule, not an assessed animal state.
* **Compatibility:** **none.** No temperature, humidity, thermal or body-temperature column (keyword
  search returned none). Room sensor values are mentioned in the description but not included.
* **Auxiliary result (descriptive):** mean fraction of frames with drinking rose from 0.013 (TN) to
  0.055 (HS), higher in HS for 23/24 pigs. Lying fraction 0.844 (TN) vs 0.803 (HS), higher in HS for only
  9/24 pigs. This supports the insight to keep drinkers available. It is not used by the classifier.

## 2. INRAE core body temperature during simulated heat waves

* **Author/contact:** Renaudeau D. (INRAE). Recherche Data Gouv, **version 3.1** (2025-12-19).
  **Licence:** Etalab 2.0 (open, attribution required).
* **Files:** `File 2 - Core body temperature_raw data.tab` → `bt_raw.tab` (MD5 `6c3a0ac6…` verified;
  Dataverse lists 185,261,834 bytes but serves 185,261,961 bytes with the matching MD5).
  `File 1 - …metadata.tab` → `bt_metadata.tab` (the served copy is re-serialised, 17,835 vs 17,750
  bytes, so the published MD5 cannot be matched; SHA-256 recorded). `File- 0 - metadata.docx` (MD5 verified).
* **Setting:** 6 trials at INRAE UE 3P (France). Growing-finishing pigs with a sensor implanted in the
  brachiocephalic muscle, thermoneutral (≈22 °C) for ≥ 7 days, then a 4–5-day challenge at ≈32 °C.
  Individual or small-group housing, ad libitum feed and water.
* **Contents:** 1,478,205 rows, 195 pigs, 202 challenge ids, 2014-09-08 to 2024-02-23, sampled every
  2 or 5 minutes. Columns: `id_challenge, ordre_challenge, porc, age, stage, datetime, T_IM, T,
  date_stress, periode, Jour, jour_debut_stress, temps_relatif_jour, ADFI`. Units: `T_IM`/`T` °C,
  `ADFI` g/day, `age` days.
* **Quality issues found:** 153,061 rows (9 pigs) have no challenge id; 304,697 have no age; 4,432 no
  ambient T; 143,475 no ADFI; 381 date-only timestamps. **30,942 rows labelled thermoneutral have
  T = 32 °C** (inconsistent period coding).
* **Critical finding:** ambient `T` takes only **three values: 22, 24 and 32 °C**. These are room
  setpoints, not continuous measurements. Correlation with core temperature is 0.45.
* **Labels:** the period variable (thermoneutral / temperature rise / heat stress), set by the
  experimental design.
* **Compatibility:** **none for the classifier.** It contains core temperature (not the AMG8833's
  apparent surface temperature, which is not interchangeable with it), no humidity, and no thermal
  array. A model on ambient T could only learn "32 °C ⇒ heat stress" and would have no support between
  24 and 32 °C or above 32 °C, which are exactly the values a Philippine pen produces.
* **Auxiliary result (descriptive):** relative to each pig's own thermoneutral median, core
  temperature during the 32 °C challenge rose by a mean of **+0.63 °C** (median +0.60, 90th percentile
  +1.3, 99th +1.9). By challenge day 0–4 the mean rise was +0.67, +0.71, +0.66, +0.55, +0.53 °C. During
  thermoneutrality the deviation was −0.03 °C (90th percentile +0.4). Used in docs/ACTIONABLE_INSIGHTS.md
  to explain why sustained heat matters; it does not define any PRISM label.

## 3. Why no "pre-training" or transfer learning was done

The classifier's input features (feature contract v1) are DHT22 air temperature, humidity, THI and
AMG8833 frame summaries. Neither external dataset contains any of them except a setpoint-only ambient
temperature, and neither contains Good / Needs Attention / High Risk or any reviewer-assessed state.
Training on them would mean (a) inventing a mapping from core temperature to surface temperature and
(b) inventing label cut-offs. The brief forbids both. Tree models are not fine-tuned in the
neural-network sense; they would be retrained on local data anyway. Pre-training therefore offers no
testable benefit and was not attempted.

## 4. Local PRISM data (to be collected)

Format: `ml/templates/readings_template.csv` and `ml/templates/label_sessions_template.csv`. Only
`farms/{farmId}/sensor_readings` (written by the API ingestion endpoint) stores full frames. Procedure:
docs/FARM_DATA_COLLECTION_AND_RETRAINING.md.

## 5. References used by the insight text (not training data)

* Vermeer H.M. & Aarnink A.J.A. (2023). *Review on heat stress in pigs on farm.* EURCAW-Pigs v1.0,
  doi:10.5281/zenodo.7620726, CC-BY-4.0 (peer reviewed).
* Adafruit AMG8833 guide (0–80 °C, ±2.5 °C) and DHT guide (DHT22: 0–100 % RH ±2–5 %, −40–80 °C ±0.5 °C).
