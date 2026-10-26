"""Builds the synthetic farm training dataset.  Run:  python -m ml.make_datasets"""
import numpy as np
import pandas as pd
from ml.features import *

rng = np.random.default_rng(42)
N_FARM = 8000

# ---------------- FARM-LEVEL ----------------
ambient = rng.normal(29, 4, N_FARM).clip(20, 40)
rh = rng.normal(75, 12, N_FARM).clip(40, 100)
body = 33.5 + 0.2 * (ambient - 28) + rng.normal(0, 0.9, N_FARM)
elevated = rng.random(N_FARM) < 0.08                       # some pigs run hot for non-ambient reasons
body = (body + elevated * rng.uniform(1.0, 2.0, N_FARM)).clip(30, 41)

farm = pd.DataFrame({"body_temp": body.round(2), "ambient_temp": ambient.round(2),
                     "humidity": rh.round(1)})
farm["thi"] = [compute_thi(t, h) for t, h in zip(farm.ambient_temp, farm.humidity)]
farm["status"] = [farm_label(t, b) for t, b in zip(farm.thi, farm.body_temp)]
farm.to_csv("data/farm_dataset.csv", index=False)
print("FARM class balance:\n", farm.status.value_counts(normalize=True).round(3))

