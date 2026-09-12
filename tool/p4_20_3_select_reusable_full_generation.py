#!/usr/bin/env python3
"""Select the newest successful Full Residual run that actually owns frozen generation artifacts.

This deliberately distinguishes a reusable *producer generation* from later successful
reuse-only consumer runs. A reuse-only run may be authoritative for its consumer head,
but it must never be mistaken for the producer of closure/materialization artifacts.

No GCIS/FIA acquisition is performed here.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Mapping, Sequence

CLOSURE_PREFIX = "p4-20-3-full-residual-closure-"
MATERIALIZATION_PREFIX = "p4-20-3-legal-enrichment-materialization-"


class SelectionError(RuntimeError):
    pass


def _artifact_id(artifacts: Sequence[Mapping[str, Any]], name: str) -> int | None:
    matches = [
        int(a["id"])
        for a in artifacts
        if a.get("name") == name and a.get("expired") is False and a.get("id") is not None
    ]
    if len(matches) > 1:
        raise SelectionError(f"DUPLICATE_UNEXPIRED_ARTIFACT:{name}")
    return matches[0] if matches else None


def select_artifact_bearing_producer(
    runs: Sequence[Mapping[str, Any]],
    artifacts_by_run: Mapping[str, Sequence[Mapping[str, Any]]],
    *,
    current_run_id: str,
) -> dict[str, Any]:
    """Return newest successful run that owns both frozen-generation artifacts.

    `runs` must already be ordered newest-first, matching GitHub Actions API ordering.
    Reuse-only successful runs are skipped rather than treated as failures.
    """
    inspected: list[dict[str, Any]] = []
    for run in runs:
        run_id = str(run.get("id", ""))
        head = str(run.get("head_sha", ""))
        if not run_id or not head:
            continue
        if run_id == str(current_run_id):
            continue
        if run.get("conclusion") not in (None, "success"):
            continue

        artifacts = list(artifacts_by_run.get(run_id, ()))
        closure_name = f"{CLOSURE_PREFIX}{head}"
        materialization_name = f"{MATERIALIZATION_PREFIX}{head}"
        closure_id = _artifact_id(artifacts, closure_name)
        materialization_id = _artifact_id(artifacts, materialization_name)
        inspected.append(
            {
                "run_id": run_id,
                "head_sha": head,
                "closure_present": closure_id is not None,
                "materialization_present": materialization_id is not None,
            }
        )
        if closure_id is not None and materialization_id is not None:
            return {
                "schema_version": 1,
                "gate": "P4.20.3-artifact-bearing-full-generation-selector",
                "producer_run_id": int(run_id),
                "producer_head": head,
                "closure_artifact_id": closure_id,
                "materialization_artifact_id": materialization_id,
                "reuse_only_success_runs_skipped": sum(
                    1
                    for x in inspected[:-1]
                    if not (x["closure_present"] and x["materialization_present"])
                ),
                "inspected": inspected,
            }

    raise SelectionError("NO_ARTIFACT_BEARING_PRIOR_FULL_GENERATION")


def _load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _self_test() -> None:
    producer_head = "8" * 40
    reuse_head = "9" * 40
    runs = [
        {"id": 49, "head_sha": reuse_head, "conclusion": "success"},
        {"id": 41, "head_sha": producer_head, "conclusion": "success"},
    ]
    artifacts = {
        "49": [
            {"id": 4901, "name": f"p4-20-3-full-residual-generation-gate-{reuse_head}", "expired": False}
        ],
        "41": [
            {"id": 4101, "name": f"{CLOSURE_PREFIX}{producer_head}", "expired": False},
            {"id": 4102, "name": f"{MATERIALIZATION_PREFIX}{producer_head}", "expired": False},
        ],
    }
    out = select_artifact_bearing_producer(runs, artifacts, current_run_id="51")
    assert out["producer_run_id"] == 41
    assert out["producer_head"] == producer_head
    assert out["closure_artifact_id"] == 4101
    assert out["materialization_artifact_id"] == 4102
    assert out["reuse_only_success_runs_skipped"] == 1

    expired = {
        "41": [
            {"id": 4101, "name": f"{CLOSURE_PREFIX}{producer_head}", "expired": True},
            {"id": 4102, "name": f"{MATERIALIZATION_PREFIX}{producer_head}", "expired": False},
        ]
    }
    try:
        select_artifact_bearing_producer([runs[1]], expired, current_run_id="51")
    except SelectionError as exc:
        assert str(exc) == "NO_ARTIFACT_BEARING_PRIOR_FULL_GENERATION"
    else:
        raise AssertionError("expired producer artifact must fail closed")

    duplicate = {
        "41": [
            {"id": 1, "name": f"{CLOSURE_PREFIX}{producer_head}", "expired": False},
            {"id": 2, "name": f"{CLOSURE_PREFIX}{producer_head}", "expired": False},
            {"id": 3, "name": f"{MATERIALIZATION_PREFIX}{producer_head}", "expired": False},
        ]
    }
    try:
        select_artifact_bearing_producer([runs[1]], duplicate, current_run_id="51")
    except SelectionError as exc:
        assert str(exc).startswith("DUPLICATE_UNEXPIRED_ARTIFACT:")
    else:
        raise AssertionError("duplicate artifact authority must fail closed")

    print("P4_20_3_ARTIFACT_BEARING_GENERATION_SELECTOR_SELF_TEST=PASS")


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--runs-json", type=Path)
    parser.add_argument("--artifacts-by-run-json", type=Path)
    parser.add_argument("--current-run-id")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)

    if args.self_test:
        _self_test()
        return 0

    required = (args.runs_json, args.artifacts_by_run_json, args.current_run_id, args.output)
    if any(x is None for x in required):
        parser.error("selection mode requires --runs-json, --artifacts-by-run-json, --current-run-id, --output")

    runs_payload = _load(args.runs_json)
    runs = runs_payload.get("workflow_runs", runs_payload) if isinstance(runs_payload, dict) else runs_payload
    artifacts_by_run = _load(args.artifacts_by_run_json)
    result = select_artifact_bearing_producer(runs, artifacts_by_run, current_run_id=str(args.current_run_id))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SelectionError as exc:
        print(f"P4_20_3_GENERATION_SELECTOR_FAIL={exc}", file=sys.stderr)
        raise SystemExit(2)
