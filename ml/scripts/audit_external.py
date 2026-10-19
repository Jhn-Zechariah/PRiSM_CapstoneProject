"""Compute the feasibility audit of the external datasets from the raw files.

    python scripts/audit_external.py
Writes data/metadata/external_audit.json and reports/external_dataset_audit.md.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from prism_ml.data.external_audit import run  # noqa: E402

if __name__ == "__main__":
    run()
    print((Path(__file__).resolve().parent.parent / "reports" / "external_dataset_audit.md").read_text(encoding="utf-8"))
