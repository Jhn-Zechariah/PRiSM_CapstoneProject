"""Retraining job: Validate -> Prepare -> Train -> Evaluate (gate). It NEVER deploys.

  python -m forecast.retrain run --dataset exports/<dataset_version> [--by NAME]
  python -m forecast.retrain run --latest                  # newest export (for a scheduler)
  python -m forecast.retrain approve <model_version> --by NAME [--note TEXT]
  python -m forecast.retrain jobs

Same inputs as the API (POST /admin/retrain). Activation and rollback are separate admin
actions on the running API (POST /models/{v}/activate, POST /models/rollback), because
the API holds the active model in memory.

Steps (each run gets a record in models/registry/jobs/<job_id>/job.json):
  1. read ONLY a Phase-1 export folder (manifest + readings) and its dataset_version
  2. run the Phase-3 experiment unchanged (same features, gapped splits, baselines)
  3. refit the validation-chosen candidate and register it as status "candidate"
  4. gate: the team's acceptance rule must pass against the baselines AND against the
     current production model on the same held-out test rows -> "eligible" or "rejected"
  5. an admin approves an eligible model ("approved"); only then can it be activated
The job id is derived from dataset_version + config hash, so repeating a request for the
same data and config returns the earlier result instead of creating another model.
"""
import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

from app.registry import Registry, RegistryError
from app.settings import ROOT, api_config, registry_path
from assess import config as acfg_mod
from forecast import evaluate as ev
from forecast.data import load_export, to_grid
from forecast.features import build_frame
from forecast.register import register, report_gate
from forecast.run import load_config, run_experiment
from pipeline.config import config_fingerprint

FINAL = ("eligible", "rejected")


def _now():
    return datetime.now(timezone.utc).isoformat()


def job_id_for(dataset_version, config_sha):
    return re.sub(r"[^A-Za-z0-9._-]", "-", f"job-{dataset_version[-24:]}-{config_sha[:10]}")


def plan(registry, dataset_dir, fcfg=None, acfg=None):
    """(job_id, existing record or None). Raises RegistryError(404) for a bad dataset."""
    fcfg, acfg = fcfg or load_config(), acfg or acfg_mod.load()
    mf = Path(dataset_dir) / "manifest.json"
    if not mf.is_file():
        raise RegistryError(f"no Phase-1 export at {dataset_dir} (manifest.json missing)", 404)
    dsv = json.loads(mf.read_text(encoding="utf-8"))["dataset_version"]
    jid = job_id_for(dsv, config_fingerprint(fcfg, acfg["assessment"]))
    try:
        existing = registry.job(jid)
    except RegistryError:
        existing = None
    return jid, existing


def production_comparison(registry, frame, split, feats, fcfg, horizon, hr, rule):
    """Second half of the gate: candidate vs the active production model on the SAME
    held-out test rows. Returns a dict with passed / reason / metrics."""
    active = registry.read_pointer().get("active")
    if not active:
        return {"available": False, "passed": True,
                "reason": "no production model is active; the gate used the baselines only"}
    try:
        model, meta = registry.load(active)
    except RegistryError as e:
        return {"available": True, "version": active, "passed": False,
                "reason": f"production model could not be loaded for comparison ({e})"}
    mismatch = [k for k, a, b in (("target", meta.get("target"), fcfg["target"]),
                                  ("horizon_minutes", meta.get("horizon_minutes"), horizon),
                                  ("predict", meta.get("predict"), fcfg["predict"]),
                                  ("features", meta.get("features"), feats)) if a != b]
    if mismatch:
        return {"available": True, "version": active, "passed": False,
                "reason": f"production model is not comparable (differs in {mismatch}); review manually"}
    dev, test = frame[split["dev"]], frame[split["test"]]
    cand = hr["best_candidate"]
    preds = {"candidate": ev.fit_predict(cand, hr["chosen_params"][cand], dev, test, feats, fcfg),
             "production": ev.to_level(model.predict(test[feats].to_numpy(dtype=float)), test, fcfg)}
    code, n_days = ev.day_index(test)
    stats = ev.error_stats(test["y_level"].to_numpy(), preds, "production", code, n_days,
                           ev.resample_matrix(n_days, fcfg), fcfg)
    metric = rule["metric"]
    cv, pv = stats["candidate"][metric], stats["production"][metric]
    checks = []
    if rule.get("min_improvement_pct") is not None:
        imp = (pv - cv) / pv * 100 if pv else float("-inf")
        checks.append({"check": f"{metric} improvement over production >= {rule['min_improvement_pct']}%",
                       "value": round(imp, 2), "pass": imp >= rule["min_improvement_pct"]})
    if rule.get("require_ci_excludes_zero"):
        ci = stats["candidate"]["vs_best_baseline"][f"{metric}_diff_ci"]
        checks.append({"check": f"95% CI of {metric} difference vs production entirely below 0",
                       "value": ci, "pass": bool(ci) and ci[1] < 0})
    if not checks:
        checks.append({"check": f"{metric} not worse than production", "value": [cv, pv], "pass": cv <= pv})
    passed = all(c["pass"] for c in checks)
    return {"available": True, "version": active, "passed": passed, "checks": checks,
            "candidate": stats["candidate"], "production": stats["production"],
            "note": "production was refit on its own (older) data, which may overlap this test period; "
                    "this favours production, so the comparison is conservative for the candidate",
            "reason": "candidate beats production under the acceptance rule" if passed
                      else "candidate does not beat the production model under the acceptance rule"}


def run_job(registry, dataset_dir, by, trigger, lock=None, fcfg=None, acfg=None):
    """Runs one job end to end and returns its record. `lock` may already be held by the
    caller (the API acquires it before answering 202); otherwise it is acquired here."""
    fcfg, acfg = fcfg or load_config(), acfg or acfg_mod.load()
    jid, existing = plan(registry, dataset_dir, fcfg, acfg)
    if existing and existing.get("status") in FINAL:
        if lock:
            lock.release()
        return {**existing, "duplicate_request": True}
    lock = lock or registry.lock(f"retrain {jid} by {by}").acquire()
    record = {
        "job_id": jid, "status": "running", "trigger": trigger, "requested_by": by,
        "requested_at": _now(), "finished_at": None, "dataset_dir": str(dataset_dir),
        "dataset_version": None, "record_count": None, "independent_days": None,
        "feature_schema": None, "config": fcfg, "config_sha256": config_fingerprint(fcfg, acfg["assessment"]),
        "assessment_config_version": acfg["version"], "seed": fcfg["seed"],
        "previous_version": registry.read_pointer().get("active"), "candidate_version": None,
        "metrics": None, "gate": None, "rejection_reason": None, "error": None,
        "previous_attempts": (existing or {}).get("previous_attempts", []) + ([existing] if existing else []),
    }
    try:
        registry.write_job(record)
        report_dir = registry.jobs_dir / jid / "report"
        rep, out, code = run_experiment(dataset_dir, fcfg, acfg, report_dir)
        record.update(dataset_version=rep["dataset_version"], record_count=rep["data_summary"].get("raw_records"),
                      independent_days=rep["sufficiency"]["independent_days"], report=str(out / "report.json"),
                      validity=rep["validity"])
        rule = fcfg.get("acceptance_rule")
        if code != 0:
            return _finish(registry, record, "rejected", f"experiment stopped: {rep['stop']['message']} "
                                                         f"Needed: {rep['stop']['needed']}")
        if not rule or not str(rule.get("horizon_minutes", "")).isdigit():
            return _finish(registry, record, "rejected",
                           "no complete acceptance_rule in config/forecast.json; nothing can be evaluated")
        h = int(rule["horizon_minutes"])
        hr = rep["horizons"].get(str(h)) or {}
        if hr.get("status") != "completed":
            return _finish(registry, record, "rejected", f"horizon {h} not evaluated: {hr.get('reason')}")
        record["feature_schema"] = rep["features"]
        _, meta = register(out / "report.json", dataset_dir, h, registry.root, fcfg, acfg)
        record["candidate_version"] = meta["version"]
        record["metrics"] = {"candidate": hr["test"][hr["best_candidate"]],
                             "best_baseline": {hr["best_baseline"]: hr["test"][hr["best_baseline"]]}}

        ok, why = report_gate(rep, h, hr["best_candidate"], meta["dataset_synthetic"])
        gate = {"vs_baselines": {"passed": ok, "reason": why, "acceptance": rep["acceptance"]}}
        if ok:
            df, _ = load_export(dataset_dir)
            grid, _ = to_grid(df, fcfg, acfg)
            frame, feats = build_frame(grid, fcfg, h)
            split = ev.make_splits(frame, fcfg, h)
            gate["vs_production"] = production_comparison(registry, frame, split, feats, fcfg, h, hr, rule)
            ok = gate["vs_production"]["passed"]
            why = gate["vs_production"]["reason"]
        record["gate"] = gate
        status = "eligible" if ok else "rejected"
        registry.set_status(meta["version"], status, f"job {jid}", why, allowed_from=("candidate",))
        return _finish(registry, record, status, None if ok else why)
    except (Exception, SystemExit) as e:       # register() raises SystemExit for refused inputs
        record["error"] = f"{type(e).__name__}: {e}"[:1000]
        return _finish(registry, record, "failed", None)
    finally:
        lock.release()


def _finish(registry, record, status, reason):
    record.update(status=status, rejection_reason=reason, finished_at=_now())
    registry.write_job(record)
    return record


def latest_export(exports_dir):
    found = []
    for mf in Path(exports_dir).glob("*/manifest.json"):
        m = json.loads(mf.read_text(encoding="utf-8"))
        found.append((m.get("created_at_utc") or "", mf.parent))
    if not found:
        raise SystemExit(f"no exports in {exports_dir}")
    return max(found)[1]


def default_registry():
    return Registry(registry_path(), api_config()["registry"])


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    src = r.add_mutually_exclusive_group(required=True)
    src.add_argument("--dataset")
    src.add_argument("--latest", action="store_true")
    r.add_argument("--by", default="cli")
    a = sub.add_parser("approve")
    a.add_argument("version")
    a.add_argument("--by", required=True)
    a.add_argument("--note", default="")
    sub.add_parser("jobs")
    args = p.parse_args(argv)

    reg = default_registry()
    if args.cmd == "jobs":
        for j in reg.jobs():
            print(j["job_id"], j["status"], j.get("candidate_version"), j.get("rejection_reason") or j.get("error") or "")
        return 0
    if args.cmd == "approve":
        from app.registry import ModelState
        meta = ModelState(reg).approve(args.version, by=args.by, note=args.note)
        print(f"{args.version} -> {meta['status']}")
        return 0
    ds = latest_export(ROOT / api_config()["retrain"]["exports_dir"]) if args.latest else Path(args.dataset)
    rec = run_job(reg, ds, by=args.by, trigger="schedule" if args.latest else "cli")
    print(json.dumps({k: rec.get(k) for k in ("job_id", "status", "candidate_version", "previous_version",
                                              "rejection_reason", "error", "duplicate_request")}, indent=2))
    return 0 if rec["status"] in FINAL else 1


if __name__ == "__main__":
    sys.exit(main())
