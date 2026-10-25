"""Rule-based and statistical assessments (not trained models).

  thi_band.assess_thi             B1  THI risk band from DHT22 temperature + humidity   (rule)
  growth.assess_growth            A1  growth trend from the pig's own manual weigh-ins  (rule)
  growth.add_pen_comparison       A1  each pig's ADG vs the pen median (comparison only)
  pen_thermal.assess_pen_thermal  A2  pen-level AMG8833 reading vs ambient-binned baseline (statistical)

Every numeric setting, formula and label comes from config/assessment.json and
config/labels.json. All results use the schema built in assess/response.py.
"""
