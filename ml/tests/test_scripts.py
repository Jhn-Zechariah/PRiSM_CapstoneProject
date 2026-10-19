import os
import subprocess
import sys
from pathlib import Path

ML = Path(__file__).resolve().parent.parent


def run(args, tmp_path, artifacts=None):
    env = {**os.environ, "PRISM_ARTIFACTS_DIR": str(artifacts or tmp_path / "art")}
    return subprocess.run([sys.executable, *args], cwd=ML, env=env, capture_output=True, text=True, timeout=300)


def test_train_cli_refuses_without_trusted_labels(tmp_path):
    # ml/data/raw/local contains no genuine labelled data yet (calibration phase)
    r = run(["scripts/train.py"], tmp_path)
    assert r.returncode == 2 and "NOT TRAINED" in r.stdout


def test_registry_cli_list_and_rollback_on_empty(tmp_path):
    r = run(["scripts/registry.py", "list"], tmp_path)
    assert r.returncode == 0 and '"approved": null' in r.stdout
    r = run(["scripts/registry.py", "approve", "missing-model", "--by", "tester"], tmp_path)
    assert r.returncode == 1 and "Unknown model" in r.stdout


def test_registry_cli_compare(tmp_path, trained_fixture_registry):
    reg, _, _ = trained_fixture_registry
    r = run(["scripts/registry.py", "compare", "fixture-model-a"], tmp_path, artifacts=reg.root)
    assert r.returncode == 0 and "candidate fixture-model-a" in r.stdout
