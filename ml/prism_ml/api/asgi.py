"""ASGI entry point:  uvicorn prism_ml.api.asgi:app --host 127.0.0.1 --port 8000"""
import logging

from prism_ml.api.main import create_app

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
app = create_app()
