import json

import pandas as pd
import pytest

from fixtures import write_fixture_dataset
from prism_ml.data.local_dataset import (DatasetError, load_local_dataset, requirements_report, split_trusted_labels)
from prism_ml.data.splits import assert_disjoint, temporal_group_split


@pytest.fixture
def fixture_root(tmp_path):
    return write_fixture_dataset(tmp_path / "local", n_sessions=12, per_session=5)


def test_fixtures_refused_for_training(fixture_root):
    with pytest.raises(DatasetError, match="Synthetic test fixtures"):
        load_local_dataset(fixture_root)


def test_empty_directory_gives_empty_dataset(tmp_path):
    ds = load_local_dataset(tmp_path / "nothing")
    assert len(ds.frame) == 0 and ds.summary["labeled_readings"] == 0
    assert requirements_report(ds)  # insufficient


def test_loads_and_labels_by_session(fixture_root):
    ds = load_local_dataset(fixture_root, allow_fixtures=True)
    assert ds.summary["labeled_readings"] == 60
    assert ds.summary["contains_synthetic_fixtures"] is True
    assert set(ds.frame["status"]) == {"Good", "Needs Attention", "High Risk"}
    assert ds.frame.groupby("label_session_id").size().eq(5).all()


def _labels(root):
    return pd.read_csv(root / "labels" / "fixture_labels.csv", dtype=str, keep_default_na=False)


@pytest.mark.parametrize("col,value,reason", [
    ("label_confidence", "probable", "not_confirmed"),
    ("reviewer_role", "farm_owner", "reviewer_role_not_accepted"),
    ("reviewer_blinded", "false", "reviewer_not_blinded"),
    ("protocol_version", "v0", "unsupported_protocol"),
    ("status", "Heat Stroke", "unknown_status"),
])
def test_untrusted_labels_are_separated(fixture_root, col, value, reason):
    labels = _labels(fixture_root)
    labels.loc[0, col] = value
    trusted, untrusted = split_trusted_labels(labels)
    assert len(untrusted) == 1 and untrusted.iloc[0]["untrusted_reason"] == reason
    assert labels.loc[0, "label_session_id"] not in set(trusted["label_session_id"])


def test_overlong_window_untrusted(fixture_root):
    labels = _labels(fixture_root)
    labels.loc[0, "window_end"] = "2027-01-01T00:00:00+00:00"
    _, untrusted = split_trusted_labels(labels)
    assert untrusted.iloc[0]["untrusted_reason"] == "window_length_invalid"


def test_conflicting_labels_dropped(fixture_root):
    labels = _labels(fixture_root)
    dup = labels.iloc[[0]].copy()
    dup["label_session_id"] = "S-conflict"
    dup["status"] = "High Risk" if labels.iloc[0]["status"] != "High Risk" else "Good"
    pd.concat([labels, dup]).to_csv(fixture_root / "labels" / "fixture_labels.csv", index=False)
    ds = load_local_dataset(fixture_root, allow_fixtures=True)
    assert ds.summary["readings_with_conflicting_labels_dropped"] == 5
    assert ds.summary["labeled_readings"] == 55


def test_quality_layer_applied_during_training_load(fixture_root):
    path = fixture_root / "readings" / "fixture_readings.csv"
    df = pd.read_csv(path, dtype=str, keep_default_na=False)
    df.loc[0, "thermal_valid"] = "false"
    df.loc[1, "thermal_pixels_c"] = json.dumps([30.0] * 64)
    df.loc[2, "air_temp_c"] = ""
    df.to_csv(path, index=False)
    ds = load_local_dataset(fixture_root, allow_fixtures=True)
    assert ds.summary["labeled_readings"] == 57
    assert ds.summary["readings_rejected_by_quality_layer"] == {"sensor_flag_invalid": 1, "flat_frame": 1, "missing_value": 1}


def test_unknown_origin_rejected(fixture_root):
    path = fixture_root / "readings" / "fixture_readings.csv"
    df = pd.read_csv(path, dtype=str, keep_default_na=False)
    df["data_origin"] = "made_up"
    df.to_csv(path, index=False)
    with pytest.raises(DatasetError, match="Unknown data_origin"):
        load_local_dataset(fixture_root)


def test_missing_columns_rejected(fixture_root):
    path = fixture_root / "readings" / "fixture_readings.csv"
    pd.read_csv(path).drop(columns=["thermal_valid"]).to_csv(path, index=False)
    with pytest.raises(DatasetError, match="missing columns"):
        load_local_dataset(fixture_root, allow_fixtures=True)


def test_temporal_group_split_is_disjoint_and_latest(fixture_root):
    ds = load_local_dataset(fixture_root, allow_fixtures=True)
    f = ds.frame.reset_index(drop=True)
    tr, te = temporal_group_split(f, "label_session_id", "window_start", 0.25)
    assert_disjoint(f, tr, te, "label_session_id")
    assert f.loc[te, "window_start"].min() > f.loc[tr, "window_start"].max()
    assert f.loc[te, "label_session_id"].nunique() == 3
