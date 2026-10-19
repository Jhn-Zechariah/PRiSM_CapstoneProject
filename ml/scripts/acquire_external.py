"""Download and checksum-verify the external candidate datasets.

    python scripts/acquire_external.py                 # all datasets in configs/datasets.json
    python scripts/acquire_external.py --dataset hotpig
    python scripts/acquire_external.py --from-dir D:/downloads   # verify + copy files already downloaded
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from prism_ml.data.acquire import acquire  # noqa: E402


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--dataset", action="append", help="dataset key (repeatable); default: all")
    p.add_argument("--from-dir", type=Path, help="directory containing <key>/<file> copies to verify instead of downloading")
    args = p.parse_args()
    for r in acquire(args.dataset, args.from_dir):
        print(f"{r['dataset']:>14}  {r['file']:<18} {r['bytes']:>11,d} B  md5 verified={r['md5_verified_against_publisher']}  sha256={r['sha256'][:16]}...")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
