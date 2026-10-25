"""Loads assessment config + labels, and evaluates config formulas safely (no eval())."""
import ast
import copy
import hashlib
import json
import operator
from pathlib import Path

from pipeline.config import load_validation

CONFIG_DIR = Path(__file__).resolve().parent.parent / "config"
ROOT_DIR = CONFIG_DIR.parent


def _read(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def load(assessment_path=None, labels_path=None):
    """Returns {"assessment", "labels", "validation", "version"}."""
    a = _read(assessment_path or CONFIG_DIR / "assessment.json")
    lab = _read(labels_path or CONFIG_DIR / "labels.json")
    return build(a, lab)


def build(assessment, labels):
    """Same as load() but from dicts (tests use this with modified copies)."""
    blob = json.dumps([assessment, labels], sort_keys=True, separators=(",", ":")).encode()
    version = (f"assessment-{assessment['version']}/labels-{labels['version']}"
               f"+{hashlib.sha256(blob).hexdigest()[:8]}")
    return {"assessment": copy.deepcopy(assessment), "labels": copy.deepcopy(labels),
            "validation": load_validation(), "version": version}


def resolve_path(p):
    p = Path(p)
    return p if p.is_absolute() else ROOT_DIR / p


# ---- safe arithmetic formula evaluation ----
_BIN = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
        ast.Div: operator.truediv, ast.Pow: operator.pow}
_UNARY = {ast.USub: operator.neg, ast.UAdd: operator.pos}


def compile_formula(expression, variables):
    """Parses an arithmetic expression that may use only + - * / ** ( ) numbers and the
    names in `variables`. Returns f(**values) -> float. Raises ValueError otherwise."""
    tree = ast.parse(expression, mode="eval")
    allowed = set(variables)
    for node in ast.walk(tree):
        if isinstance(node, ast.Name):
            if node.id not in allowed:
                raise ValueError(f"unknown variable {node.id!r} in formula")
        elif isinstance(node, ast.Constant):
            if not isinstance(node.value, (int, float)) or isinstance(node.value, bool):
                raise ValueError("only numeric constants are allowed in formulas")
        elif not isinstance(node, (ast.Expression, ast.BinOp, ast.UnaryOp, ast.Load,
                                   *_BIN, *_UNARY)):
            raise ValueError(f"operation {type(node).__name__} not allowed in formulas")

    def ev(n, env):
        if isinstance(n, ast.Expression):
            return ev(n.body, env)
        if isinstance(n, ast.Constant):
            return float(n.value)
        if isinstance(n, ast.Name):
            return float(env[n.id])
        if isinstance(n, ast.BinOp):
            return _BIN[type(n.op)](ev(n.left, env), ev(n.right, env))
        return _UNARY[type(n.op)](ev(n.operand, env))

    return lambda **env: ev(tree, env)
