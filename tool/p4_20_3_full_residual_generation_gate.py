#!/usr/bin/env python3
"""P4.20.3 full-residual generation reuse gate.

This module decides whether a PR-head change needs another expensive GCIS
full-residual acquisition or can reuse the latest successful generation
authority.  It intentionally does not inspect merchant names or emit
responsible-person data.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Iterable

SCHEMA_VERSION = 1
GATE = "P4.20.3-full-residual-generation-gate"
POLICY_VERSION = "p4.20.3-full-residual-generation-v1"

SEMANTIC_INPUTS = {
    "tool/p4_20_3_stage_fia_registry.py",
    "tool/p4_20_3_acquire_gcis_registration_type.py",
}
EXPLICIT_REQUEST = "authority/p4_20_3_full_acquisition_request.json"
ESTIMATED_FULL_RUN_LINUX_MINUTES = 1250


def _sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _normalized_paths(paths: Iterable[str]) -> list[str]:
    return sorted({p.strip().replace("\\", "/") for p in paths if p.strip()})


def decide(
    *,
    current_head: str,
    prior_success_head: str,
    prior_run_id: int,
    prior_closure_artifact_id: int,
    prior_materialization_artifact_id: int | None,
    prior_source_last_modified: str,
    prior_source_archive_sha256: str,
    current_source_last_modified: str,
    changed_files: Iterable[str],
    stage_tool: Path,
    acquisition_tool: Path,
) -> dict:
    changed = _normalized_paths(changed_files)
    semantic_changed = sorted(set(changed) & SEMANTIC_INPUTS)
    explicit_request = EXPLICIT_REQUEST in changed
    source_probe_available = bool(current_source_last_modified.strip())
    source_changed = (
        not source_probe_available
        or current_source_last_modified.strip() != prior_source_last_modified.strip()
    )
    prior_authority_available = bool(
        prior_success_head
        and prior_run_id > 0
        and prior_closure_artifact_id > 0
        and prior_source_last_modified
        and len(prior_source_archive_sha256) == 64
    )

    reasons: list[str] = []
    if not prior_authority_available:
        reasons.append("NO_PRIOR_SUCCESS_AUTHORITY")
    if not source_probe_available:
        reasons.append("SOURCE_LAST_MODIFIED_UNAVAILABLE")
    elif source_changed:
        reasons.append("SOURCE_GENERATION_CHANGED")
    if semantic_changed:
        reasons.append("ACQUISITION_SEMANTICS_CHANGED")
    if explicit_request:
        reasons.append("EXPLICIT_FULL_ACQUISITION_REQUEST")

    run_expensive = bool(reasons)
    stage_sha = _sha256_file(stage_tool)
    acquisition_sha = _sha256_file(acquisition_tool)
    generation_basis = {
        "policy_version": POLICY_VERSION,
        "source_last_modified": (
            current_source_last_modified.strip()
            if source_probe_available
            else prior_source_last_modified.strip()
        ),
        "source_archive_sha256": prior_source_archive_sha256,
        "stage_tool_sha256": stage_sha,
        "acquisition_tool_sha256": acquisition_sha,
    }
    generation_key = hashlib.sha256(
        json.dumps(
            generation_basis,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
    ).hexdigest()

    return {
        "schema_version": SCHEMA_VERSION,
        "gate": GATE,
        "policy_version": POLICY_VERSION,
        "current_head": current_head,
        "prior_success_head": prior_success_head,
        "prior_success_run_id": prior_run_id,
        "prior_closure_artifact_id": prior_closure_artifact_id,
        "prior_materialization_artifact_id": prior_materialization_artifact_id,
        "prior_source_last_modified": prior_source_last_modified,
        "current_source_last_modified": current_source_last_modified,
        "source_archive_sha256": prior_source_archive_sha256,
        "source_probe_available": source_probe_available,
        "source_generation_changed": source_changed,
        "semantic_changed_files": semantic_changed,
        "explicit_request_changed": explicit_request,
        "changed_files": changed,
        "stage_tool_sha256": stage_sha,
        "acquisition_tool_sha256": acquisition_sha,
        "generation_key": generation_key,
        "run_expensive": run_expensive,
        "generation_artifact_reuse": not run_expensive,
        "reasons": reasons if reasons else ["SAME_GENERATION_REUSE_APPROVED"],
        "estimated_linux_minutes_avoided": (
            0 if run_expensive else ESTIMATED_FULL_RUN_LINUX_MINUTES
        ),
        "validation_subset": False,
        "responsible_person_payload_emitted": False,
        "mobile_per_invoice_network_lookup": False,
    }


def _self_test() -> None:
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        stage = root / "stage.py"
        acquire = root / "acquire.py"
        stage.write_text("stage-v1\n", encoding="utf-8")
        acquire.write_text("acquire-v1\n", encoding="utf-8")
        common = dict(
            current_head="b" * 40,
            prior_success_head="a" * 40,
            prior_run_id=123,
            prior_closure_artifact_id=456,
            prior_materialization_artifact_id=789,
            prior_source_last_modified="Sun, 06 Sep 2026 21:13:30 GMT",
            prior_source_archive_sha256="1" * 64,
            current_source_last_modified="Sun, 06 Sep 2026 21:13:30 GMT",
            stage_tool=stage,
            acquisition_tool=acquire,
        )

        downstream = decide(changed_files=["lib/example.dart"], **common)
        assert downstream["run_expensive"] is False
        assert downstream["generation_artifact_reuse"] is True
        assert downstream["estimated_linux_minutes_avoided"] == 1250

        workflow_only = decide(
            changed_files=[
                ".github/workflows/p4_20_3_gcis_residual_full_acquisition.yml"
            ],
            **common,
        )
        assert workflow_only["run_expensive"] is False

        source_change = decide(
            changed_files=["lib/example.dart"],
            **{
                **common,
                "current_source_last_modified": "Mon, 07 Sep 2026 21:13:30 GMT",
            },
        )
        assert source_change["run_expensive"] is True
        assert "SOURCE_GENERATION_CHANGED" in source_change["reasons"]

        semantic = decide(
            changed_files=["tool/p4_20_3_stage_fia_registry.py"],
            **common,
        )
        assert semantic["run_expensive"] is True
        assert semantic["semantic_changed_files"] == [
            "tool/p4_20_3_stage_fia_registry.py"
        ]

        explicit = decide(changed_files=[EXPLICIT_REQUEST], **common)
        assert explicit["run_expensive"] is True
        assert explicit["explicit_request_changed"] is True

        missing_probe = decide(
            changed_files=["docs/readme.md"],
            **{**common, "current_source_last_modified": ""},
        )
        assert missing_probe["run_expensive"] is True

    print("P4_20_3_FULL_RESIDUAL_GENERATION_GATE_SELF_TEST=PASS")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--current-head")
    parser.add_argument("--prior-success-head", default="")
    parser.add_argument("--prior-run-id", type=int, default=0)
    parser.add_argument("--prior-closure-artifact-id", type=int, default=0)
    parser.add_argument("--prior-materialization-artifact-id", type=int)
    parser.add_argument("--prior-source-last-modified", default="")
    parser.add_argument("--prior-source-archive-sha256", default="")
    parser.add_argument("--current-source-last-modified", default="")
    parser.add_argument("--changed-files-file", type=Path)
    parser.add_argument(
        "--stage-tool",
        type=Path,
        default=Path("tool/p4_20_3_stage_fia_registry.py"),
    )
    parser.add_argument(
        "--acquisition-tool",
        type=Path,
        default=Path("tool/p4_20_3_acquire_gcis_registration_type.py"),
    )
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    if args.self_test:
        _self_test()
        return 0

    required = [
        args.current_head,
        args.prior_success_head,
        args.prior_source_last_modified,
        args.prior_source_archive_sha256,
        args.changed_files_file,
        args.output,
    ]
    if any(v in (None, "") for v in required):
        parser.error("generation decision inputs are incomplete")

    changed = args.changed_files_file.read_text(encoding="utf-8").splitlines()
    result = decide(
        current_head=args.current_head,
        prior_success_head=args.prior_success_head,
        prior_run_id=args.prior_run_id,
        prior_closure_artifact_id=args.prior_closure_artifact_id,
        prior_materialization_artifact_id=args.prior_materialization_artifact_id,
        prior_source_last_modified=args.prior_source_last_modified,
        prior_source_archive_sha256=args.prior_source_archive_sha256,
        current_source_last_modified=args.current_source_last_modified,
        changed_files=changed,
        stage_tool=args.stage_tool,
        acquisition_tool=args.acquisition_tool,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        + "\n",
        encoding="utf-8",
    )
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
