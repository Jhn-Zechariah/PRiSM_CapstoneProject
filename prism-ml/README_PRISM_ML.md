# PRISM ML — Complete Implementation Guide

## Project Structure
```
prism-ml/
├── prism_farm_dataset.csv          # 1,000 farm-level training records
├── prism_pig_weight_dataset.csv    # 800 per-pig weight training records
├── prism_farm_ml.py                # Farm-Level Decision Tree (train + predict)
├── prism_pig_weight_ml.py          # Per-Pig Weight Decision Tree (train + predict)
├── prism_api.py                    # FastAPI backend (connect to PRISM app)
└── README_PRISM_ML.md              # This file
```

---

## Two Separate ML Models

| Model | File | Input | Output |
|---|---|---|---|
| Farm-Level | `prism_farm_ml.py` | temp, humidity, THI, weight_change, feed_intake | Good / Needs Attention / High Risk |
| Per-Pig Weight | `prism_pig_weight_ml.py` | age, current_weight, ADG, deviation % | Normal / Underweight / Overweight |

---

## Setup & Installation

```bash
pip install scikit-learn pandas numpy joblib fastapi uvicorn
```

---

## Step 1 — Train the Models

```bash
# Train farm-level model (saves prism_farm_model.pkl)
python prism_farm_ml.py

# Train pig weight model (saves prism_pig_weight_model.pkl)
python prism_pig_weight_ml.py
```

---

## Step 2 — Run the API

```bash
uvicorn prism_api:app --reload --port 8000
```

API will be live at: `http://localhost:8000`

---

## API Endpoints

### POST /api/farm/analyze
Analyze current farm conditions.

**Request body:**
```json
{
  "temperature_c": 30.5,
  "humidity_pct": 85.0,
  "weight_change_kg": 0.25,
  "feed_intake_kg": 1.8,
  "medicine_given": 0
}
```

**Response:**
```json
{
  "condition": "Needs Attention",
  "thi": 27.4,
  "insights": [
    "Barn temperature (30.5C) is above the thermoneutral zone.",
    "THI 27.4 — farm is in the DANGER zone."
  ],
  "recommendations": [
    "Monitor pigs closely and consider pre-cooling.",
    "Emergency: cool barn, provide cold water immediately."
  ]
}
```

---

### POST /api/pig/analyze
Analyze individual pig weight status.

**Request body:**
```json
{
  "pig_id": "PIG-042",
  "birth_date": "2025-09-01",
  "current_weight": 22.0,
  "birth_weight": 1.5
}
```

**Response:**
```json
{
  "pig_id": "PIG-042",
  "stage": "starter",
  "age_days": 81,
  "adg": 0.253,
  "classification": "Underweight",
  "insight": "Pig is at 22.0 kg — 29.0% below expected for starter stage.",
  "recommendation": "Review feeding schedule, check for illness or parasites..."
}
```

---

## Dataset Sources (APA)

- **[S1]** Lee et al. (2019). Analysis of growth performance in swine based on machine learning. *IEEE Access, 7*, 161716–161724. https://doi.org/10.1109/ACCESS.2019.2950811
- **[S2]** Rauw et al. (2020). Impact of environmental temperature on production traits in pigs. *Scientific Reports, 10*(1), 2106. https://doi.org/10.1038/s41598-020-58981-w
- **[S3]** Journal of Animal Science (2023). Effect of temperature and humidity on daily feeding behavior in swine. https://doi.org/10.1093/jas/skad046.017
- **[S4]** NRC (1981). *Effect of environment on nutrient requirements of domestic animals.* National Academies Press. https://www.ncbi.nlm.nih.gov/books/NBK232319/
- **[S6]** Animals (2022). A new approach to detecting changes in feeding behaviour in group-housed pigs. https://doi.org/10.3390/ani12121500

---

## Key Thresholds Used

### Farm-Level (Temperature + Humidity)
| Condition | Temp (C) | Humidity (%) | THI |
|---|---|---|---|
| Good | 18 – 25 | 60 – 80 | < 23.33 |
| Needs Attention | 25.1 – 32 | 80 – 90 | 23.33 – 26.11 |
| High Risk | > 32 | > 90 | > 26.11 |

### Per-Pig Weight (Growth Stages)
| Stage | Age (days) | Weight (kg) | ADG Target |
|---|---|---|---|
| Starter | 0 – 70 | 1.5 – 30 | 0.35 kg/day |
| Grower | 71 – 105 | 30 – 60 | 0.60 kg/day |
| Finisher | 106 – 160 | 60 – 100 | 0.75 kg/day |

---

*PRISM ML — Academic research use. Thresholds derived from peer-reviewed swine health literature.*
