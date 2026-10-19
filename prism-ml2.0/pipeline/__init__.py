"""Sensor data pipeline: normalise, validate (flag-only), correct and export.

Independent of the FastAPI service: nothing here imports `app`, and sensor logging
(ESP32 -> Firestore) never goes through this code.
"""
