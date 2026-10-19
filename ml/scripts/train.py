"""Train and evaluate a candidate thermal-status model from trusted local labels.

    python scripts/train.py [--model-id thermal-status-YYYYMMDD]

Exit codes: 0 = candidate registered and PASSED acceptance; 1 = candidate registered but FAILED
acceptance; 2 = not enough trusted labelled data (nothing trained). Approval is a separate step:
``python scripts/registry.py approve <model_id> --by "<name, role>"``.
"""
import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from prism_ml.config import REPORTS_DIR  # noqa: E402
from prism_ml.data.local_dataset import load_local_dataset  # noqa: E402
from prism_ml.models.train import InsufficientTrustedData, train  # noqa: E402


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--model-id")
    args = p.parse_args()
    ds = load_local_dataset()
    try:
        result = train(ds, model_id=args.model_id)
    except InsufficientTrustedData as e:
        REPORTS_DIR.mkdir(parents=True, exist_ok=True)
        path = REPORTS_DIR / f"training_attempt_{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}.json"
        path.write_text(json.dumps({"outcome": "not_trained_insufficient_trusted_data", "problems": e.problems,
                                    "dataset_summary": e.summary}, indent=2, default=str), encoding="utf-8")
        print("NOT TRAINED - insufficient trusted labelled data:")
        for prob in e.problems:
            print("  -", prob)
        print(f"report: {path}")
        return 2
    print(f"registered candidate {result.model_id}; acceptance passed={result.acceptance['passed']}")
    for f in result.acceptance["failures"]:
        print("  FAILED:", f)
    m = result.test_metrics
    print(f"held-out: macro-F1={m['macro_f1']:.3f} balanced-acc={m['balanced_accuracy']:.3f} "
          f"HighRisk recall={m['high_risk_recall']:.3f}  report: {result.report_path}")
    return 0 if result.acceptance["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
