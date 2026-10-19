"""Summarise the local labelled dataset without training (run this before scripts/train.py).

    python scripts/check_dataset.py
Shows how many readings/sessions are usable per class, why readings or labels were rejected, and which
data requirements in configs/acceptance.json are still unmet.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from prism_ml.data.local_dataset import load_local_dataset, requirements_report  # noqa: E402

if __name__ == "__main__":
    ds = load_local_dataset()
    s = dict(ds.summary)
    s.pop("reading_files", None)
    s.pop("label_files", None)
    print(json.dumps(s, indent=2, default=str))
    problems = requirements_report(ds)
    if problems:
        print("\nNOT READY TO TRAIN:")
        for p in problems:
            print("  -", p)
        raise SystemExit(2)
    print("\nREADY: enough trusted labelled data to run scripts/train.py")
