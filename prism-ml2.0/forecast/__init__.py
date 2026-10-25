"""B2 offline forecasting experiment (pen temperature / THI). See forecast/run.py.

Reads ONLY the Phase-1 export (pipeline/export.py). Never controls the pump and is not
wired into the API: a model may only be enabled if the team's acceptance rule in
config/forecast.json passes on REAL data.
"""
