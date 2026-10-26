import json

import pytest

import datasets
from datasets import build_splits, split_days_chronological, split_real_days
from simulate import simulate


def test_chronological_day_split():
    days = [f"2026-01-{d:02d}" for d in range(1, 21)]
    sp = split_days_chronological(days[::-1], {"train": 0.7, "val": 0.15, "test": 0.15})
    assert max(sp["train"]) < min(sp["val"]) <= max(sp["val"]) < min(sp["test"])
    assert sorted(sp["train"] + sp["val"] + sp["test"]) == days
    with pytest.raises(ValueError):
        split_days_chronological(days[:2], {"train": 0.7, "val": 0.15, "test": 0.15})


def test_real_holdout_is_frozen(cfg, tmp_path, monkeypatch):
    monkeypatch.setattr(datasets, "HOLDOUT_PATH", tmp_path / "real_holdout.json")
    days = [f"2026-10-{d:02d}" for d in range(1, 11)]
    sp = split_real_days(days, cfg)
    n = cfg["training"]["real_holdout_days"]
    assert sp["test"] == days[-n:]
    assert max(sp["train"]) < min(sp["val"]) and max(sp["val"]) < min(sp["test"])
    # more data arrives later: the frozen block does not move and is still excluded from training
    more = days + [f"2026-10-{d:02d}" for d in range(11, 16)]
    sp2 = split_real_days(more, cfg)
    assert sp2["test"] == days[-n:]
    assert not set(sp2["test"]) & set(sp2["train"] + sp2["val"])
    assert json.loads((tmp_path / "real_holdout.json").read_text())["days"] == days[-n:]


def test_build_splits_synthetic_is_time_ordered(cfg, tmp_path, monkeypatch):
    path = tmp_path / "syn.parquet"
    simulate(cfg, days=8, seed=1).to_parquet(path, index=False)
    monkeypatch.setattr(datasets, "SYNTHETIC_PATH", path)
    sp = build_splits("synthetic", cfg)
    assert sp["train"].index.max() < sp["val"].index.min()
    assert sp["val"].index.max() < sp["test"].index.min()
    assert not set(sp["train"]["day"]) & set(sp["test"]["day"])
