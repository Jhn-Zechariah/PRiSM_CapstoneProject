import sys
from pathlib import Path

import pytest

ML_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ML_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))


@pytest.fixture(autouse=True)
def isolated_artifacts(tmp_path, monkeypatch):
    """Every test gets an empty model registry so nothing touches ml/artifacts."""
    monkeypatch.setenv("PRISM_ARTIFACTS_DIR", str(tmp_path / "artifacts"))
    yield


@pytest.fixture(scope="session")
def trained_fixture_registry(tmp_path_factory):
    """Train once on the separable SYNTHETIC fixture and approve it in a throw-away registry."""
    from fixtures import write_fixture_dataset
    from prism_ml.data.local_dataset import load_local_dataset
    from prism_ml.models.registry import ModelRegistry
    from prism_ml.models.train import train

    root = tmp_path_factory.mktemp("fixture_data")
    write_fixture_dataset(root)
    ds = load_local_dataset(root, allow_fixtures=True)
    reg = ModelRegistry(tmp_path_factory.mktemp("fixture_artifacts"), testing_allow_fixture_models=True)
    result = train(ds, registry=reg, model_id="fixture-model-a", reports_dir=tmp_path_factory.mktemp("reports"))
    return reg, result, ds
