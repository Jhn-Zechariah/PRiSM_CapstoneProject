import json

import pytest

from fixtures import write_fixture_dataset
from prism_ml.data.local_dataset import load_local_dataset
from prism_ml.features.contract import contract_hash
from prism_ml.models.registry import ModelRegistry, RegistryError
from prism_ml.models.train import InsufficientTrustedData, train


def test_refuses_to_train_without_trusted_data(tmp_path):
    with pytest.raises(InsufficientTrustedData) as e:
        train(load_local_dataset(tmp_path / "empty"), registry=ModelRegistry(tmp_path / "a"), reports_dir=tmp_path)
    assert any("trusted labeled readings" in p for p in e.value.problems)


def test_refuses_small_dataset(tmp_path):
    ds = load_local_dataset(write_fixture_dataset(tmp_path / "d", n_sessions=9, per_session=5), allow_fixtures=True)
    with pytest.raises(InsufficientTrustedData):
        train(ds, registry=ModelRegistry(tmp_path / "a"), reports_dir=tmp_path)


def test_training_produces_registered_candidate(trained_fixture_registry):
    reg, result, ds = trained_fixture_registry
    entry = reg.list_models()["models"]["fixture-model-a"]
    assert entry["status"] in ("candidate", "approved")
    md = json.loads((reg.models_dir / "fixture-model-a" / "metadata.json").read_text())
    ev = json.loads((reg.models_dir / "fixture-model-a" / "evaluation.json").read_text())
    assert md["feature_contract_sha256"] == contract_hash()
    assert md["training_data"]["contains_synthetic_fixtures"] is True
    assert md["algorithm"] in ("decision_tree", "random_forest", "hist_gradient_boosting")
    # held-out evaluation: test sessions are disjoint from training sessions and counted
    assert md["training_data"]["test_sessions"] == 9 and md["training_data"]["train_sessions"] == 27
    assert ev["test"]["n"] == md["training_data"]["test_readings"]
    assert set(ev["cv_model_selection"]) == {"decision_tree", "random_forest", "hist_gradient_boosting"}
    assert "acceptance" in ev and isinstance(ev["acceptance"]["passed"], bool)


def test_training_is_reproducible(tmp_path, trained_fixture_registry):
    _, first, ds = trained_fixture_registry
    second = train(ds, registry=ModelRegistry(tmp_path / "b", testing_allow_fixture_models=True), model_id="fixture-model-b",
                   reports_dir=tmp_path)
    assert second.test_metrics["macro_f1"] == first.test_metrics["macro_f1"]
    assert second.test_metrics["confusion_matrix"] == first.test_metrics["confusion_matrix"]


def test_random_labels_fail_acceptance_and_cannot_be_approved(tmp_path):
    ds = load_local_dataset(write_fixture_dataset(tmp_path / "d", separable=False, seed=3), allow_fixtures=True)
    reg = ModelRegistry(tmp_path / "a", testing_allow_fixture_models=True)
    res = train(ds, registry=reg, model_id="random-labels", reports_dir=tmp_path)
    assert res.acceptance["passed"] is False and res.acceptance["failures"]
    with pytest.raises(RegistryError, match="acceptance"):
        reg.approve("random-labels", approved_by="tester")


def test_fixture_model_never_approvable_in_real_registry(trained_fixture_registry, tmp_path):
    reg, result, _ = trained_fixture_registry
    real = ModelRegistry(reg.root)  # same files, without the testing flag
    if result.acceptance["passed"]:
        with pytest.raises(RegistryError, match="synthetic"):
            real.approve("fixture-model-a", approved_by="tester")


def test_approve_load_tamper_and_rollback(tmp_path, trained_fixture_registry):
    _, _, ds = trained_fixture_registry
    reg = ModelRegistry(tmp_path / "art", testing_allow_fixture_models=True)
    r1 = train(ds, registry=reg, model_id="m-one", reports_dir=tmp_path)
    r2 = train(ds, registry=reg, model_id="m-two", reports_dir=tmp_path)
    if not (r1.acceptance["passed"] and r2.acceptance["passed"]):
        pytest.skip("fixture model did not pass acceptance; approval path covered elsewhere")
    reg.approve("m-one", approved_by="adviser")
    reg.approve("m-two", approved_by="adviser")
    assert reg.load_approved().model_id == "m-two"
    assert reg.rollback(performed_by="adviser", note="test") == "m-one"
    assert reg.load_approved().model_id == "m-one"
    # tampering with the approved artifact is detected
    (reg.models_dir / "m-one" / "model.joblib").write_bytes(b"not a model")
    with pytest.raises(RegistryError, match="Integrity"):
        reg.load_approved()


@pytest.mark.parametrize("bad", ["../escape", "UPPER", "a", "x/y"])
def test_model_id_validation(tmp_path, bad):
    with pytest.raises(RegistryError):
        ModelRegistry(tmp_path)._model_dir(bad)


def test_model_versions_are_immutable(tmp_path):
    reg = ModelRegistry(tmp_path)
    reg.register("same-id", {"x": 1}, {"training_data": {}}, {})
    with pytest.raises(RegistryError, match="immutable"):
        reg.register("same-id", {"x": 2}, {}, {})


def test_no_approved_model_returns_none(tmp_path):
    assert ModelRegistry(tmp_path).load_approved() is None
