"""Manage farm membership in the self-hosted SQLite store (PRISM_STORAGE_BACKEND=sqlite).

    python scripts/farms.py add-member <farm_id> <firebase_uid>
    python scripts/farms.py remove-member <farm_id> <firebase_uid>
"""
import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from prism_ml.api.repository import make_repository  # noqa: E402


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("action", choices=["add-member", "remove-member"])
    p.add_argument("farm_id")
    p.add_argument("uid")
    a = p.parse_args()
    repo = make_repository("sqlite", os.environ.get("PRISM_SQLITE_PATH", ""))
    (repo.add_member if a.action == "add-member" else repo.remove_member)(a.farm_id, a.uid)
    print(f"{a.action}: {a.uid} @ {a.farm_id} ({repo.path})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
