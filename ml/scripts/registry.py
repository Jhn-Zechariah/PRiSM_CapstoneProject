"""Inspect, approve and roll back model versions.

    python scripts/registry.py list
    python scripts/registry.py compare <candidate_id>      # side by side with the approved model
    python scripts/registry.py approve <model_id> --by "Name, role" [--note "..."]
    python scripts/registry.py rollback --by "Name, role" [--note "..."]

The API loads the approved model at start-up; restart it after approve/rollback.
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from prism_ml.models.registry import ModelRegistry, RegistryError  # noqa: E402


KEYS = ["macro_f1", "balanced_accuracy", "high_risk_recall", "needs_attention_recall",
        "good_predicted_when_high_risk", "multiclass_brier"]


def compare(reg: ModelRegistry, candidate: str) -> None:
    """Print held-out metrics of a candidate next to the approved model. Test sets differ between
    training runs (later sessions), so also re-check both on the same recent sessions before approving."""
    reg_data = reg.list_models()
    rows = {"candidate " + candidate: candidate}
    if reg_data.get("approved"):
        rows["approved  " + reg_data["approved"]] = reg_data["approved"]
    print(f"{'model':<48}" + "".join(f"{k[:14]:>16}" for k in KEYS) + f"{'acceptance':>12}")
    for label, mid in rows.items():
        ev = json.loads((reg._model_dir(mid) / "evaluation.json").read_text(encoding="utf-8"))
        t = ev["test"]
        vals = "".join(f"{(t.get(k) if t.get(k) is not None else float('nan')):>16.3f}" for k in KEYS)
        print(f"{label:<48}{vals}{str(ev['acceptance']['passed']):>12}")


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list")
    c = sub.add_parser("compare")
    c.add_argument("model_id")
    a = sub.add_parser("approve")
    a.add_argument("model_id")
    a.add_argument("--by", required=True)
    a.add_argument("--note", default="")
    r = sub.add_parser("rollback")
    r.add_argument("--by", required=True)
    r.add_argument("--note", default="")
    args = p.parse_args()
    reg = ModelRegistry()
    try:
        if args.cmd == "list":
            print(json.dumps(reg.list_models(), indent=2))
        elif args.cmd == "compare":
            compare(reg, args.model_id)
        elif args.cmd == "approve":
            reg.approve(args.model_id, approved_by=args.by, note=args.note)
            print(f"approved {args.model_id}")
        else:
            print(f"approved model is now: {reg.rollback(performed_by=args.by, note=args.note)}")
    except RegistryError as e:
        print(f"ERROR: {e}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
