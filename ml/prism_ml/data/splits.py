"""Leakage-resistant splitting.

Consecutive readings from the same pen and label session are strongly correlated, so they are kept
together: the held-out test set consists of the most recent label sessions (temporal hold-out) and
cross-validation uses StratifiedGroupKFold over sessions.
"""
from __future__ import annotations

import math

import pandas as pd
from sklearn.model_selection import StratifiedGroupKFold


def temporal_group_split(frame: pd.DataFrame, group_col: str, time_col: str, test_fraction: float
                         ) -> tuple[pd.Index, pd.Index]:
    starts = frame.groupby(group_col)[time_col].min().sort_values(kind="mergesort")
    n_test = max(1, math.ceil(len(starts) * test_fraction))
    test_groups = set(starts.index[-n_test:])
    is_test = frame[group_col].isin(test_groups)
    return frame.index[~is_test], frame.index[is_test]


def group_cv(n_splits: int, seed: int) -> StratifiedGroupKFold:
    return StratifiedGroupKFold(n_splits=n_splits, shuffle=True, random_state=seed)


def assert_disjoint(frame: pd.DataFrame, train_idx, test_idx, group_col: str) -> None:
    overlap = set(frame.loc[train_idx, group_col]) & set(frame.loc[test_idx, group_col])
    if overlap:
        raise AssertionError(f"Groups present in both train and test: {sorted(overlap)[:5]}")
