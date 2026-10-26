# DEPRECATED: rule-based farm Decision Tree (kept for reference only)

This is the previous PRISM farm-level model, restored from git commit `b1c90ce^`
(path `prism-ml2.0/`), where it had been deleted. It is not deployed and nothing in
`prism-ml/` imports it.

**Why it was replaced:** it was trained on 8,000 random synthetic rows whose labels came
from a threshold rule (`farm_label(thi, body_temp)` in `ml/features.py`). The tree just
learned that rule back (99.9% "accuracy"), so it was effectively rule-based. It is replaced
by the time-series forecaster in `prism-ml/` (see `prism-ml/README.md`).

**What changed while restoring it:**
- Only the farm model is kept. The per-pig growth Decision Tree (`pig_growth_model`,
  `/predict/pig-growth`, the PIC reference curve and its dataset code) was removed at the
  team's request, along with the pig-card ML block in the Flutter app.
- Generated artefacts were not restored: `data/*.csv`, `models/*.pkl` and the tree PNGs.
  Rebuild with `python -m ml.make_datasets && python -m ml.train` from this folder, or
  recover them with `git show b1c90ce^:prism-ml2.0/<path>`.
