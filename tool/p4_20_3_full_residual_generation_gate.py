#!/usr/bin/env python3
"""P4.20.3 full-residual generation reuse and paid-acquisition gate.

This module separates generation-change eligibility from paid acquisition
authorization.  A new FIA source generation or acquisition-semantic change may
require a new generation, but the expensive GCIS run is authorized only when
the exact PR-head also changes the explicit governed acquisition request.
It intentionally does not inspect merchant names or emit responsible-person
data.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Iterable

SCHEMA_VERSION = 2
GATE = "P4.20.3-full-residual-generation-gate"
POLICY_VERSION = "p4.20.3-full-residual-generation-v2-request-authorized"

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
    source_changed = bool(
        source_probe_available
        and current_source_last_modified.strip() != prior_source_last_modified.strip()
    )
    prior_authority_available = bool(
        prior_success_head
        and prior_run_id > 0
        and prior_closure_artifact_id > 0
        and prior_materialization_artifact_id is not None
        and prior_materialization_artifact_id > 0
        and prior_source_last_modified
        and len(prior_source_archive_sha256) == 64
    )

    # Unknown source state is itself a fail-closed generation hold.  It may
    # require a request, but it can never authorize paid acquisition until the
    # source probe is available again.
    generation_change_eligible = bool(
        not prior_authority_available
        or not source_probe_available
        or source_changed
        or semantic_changed
    )
    acquisition_request_required = bool(generation_change_eligible)
    acquisition_request_authorized = bool(
        explicit_request and generation_change_eligible and source_probe_available
    )

    generation_artifact_reuse = bool(
        prior_authority_available
        and source_probe_available
        and not source_changed
        and not semantic_changed
    )
    run_expensive = acquisition_request_authorized

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
    if generation_change_eligible and not explicit_request:
        reasons.append("FULL_ACQUISITION_REQUEST_REQUIRED")
    if explicit_request and not generation_change_eligible:
        reasons.append("FULL_ACQUISITION_REQUEST_REJECTED_SAME_GENERATION")
    if explicit_request and generation_change_eligible and not source_probe_available:
        reasons.append("FULL_ACQUISITION_REQUEST_BLOCKED_SOURCE_PROBE_UNAVAILABLE")
    if generation_artifact_reuse and not reasons:
        reasons.append("SAME_GENERATION_REUSE_APPROVED")

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
        "generation_change_eligible": generation_change_eligible,
        "acquisition_request_required": acquisition_request_required,
        "acquisition_request_authorized": acquisition_request_authorized,
        "changed_files": changed,
        "stage_tool_sha256": stage_sha,
        "acquisition_tool_sha256": acquisition_sha,
        "generation_key": generation_key,
        "run_expensive": run_expensive,
        "generation_artifact_reuse": generation_artifact_reuse,
        "reasons": reasons,
        "estimated_linux_minutes_avoided": (
            ESTIMATED_FULL_RUN_LINUX_MINUTES if generation_artifact_reuse else 0
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
        assert downstream["acquisition_request_required"] is False

        workflow_only = decide(
            changed_files=[
                ".github/workflows/p4_20_3_gcis_residual_full_acquisition.yml"
            ],
            **common,
        )
        assert workflow_only["run_expensive"] is False
        assert workflow_only["generation_artifact_reuse"] is True

        source_change_hold = decide(
            changed_files=["lib/example.dart"],
            **{
                **common,
                "current_source_last_modified": "Mon, 07 Sep 2026 21:11:35 GMT",
            },
        )
        assert source_change_hold["run_expensive"] is False
        assert source_change_hold["generation_artifact_reuse"] is False
        assert source_change_hold["generation_change_eligible"] is True
        assert source_change_hold["acquisition_request_required"] is True
        assert source_change_hold["acquisition_request_authorized"] is False
        assert "SOURCE_GENERATION_CHANGED" in source_change_hold["reasons"]
        assert "FULL_ACQUISITION_REQUEST_REQUIRED" in source_change_hold["reasons"]

        source_change_authorized = decide(
            changed_files=[EXPLICIT_REQUEST],
            **{
                **common,
                "current_source_last_modified": "Mon, 07 Sep 2026 21:11:35 GMT",
            },
        )
        assert source_change_authorized["run_expensive"] is True
        assert source_change_authorized["generation_artifact_reuse"] is False
        assert source_change_authorized["acquisition_request_authorized"] is True

        semantic_hold = decide(
            changed_files=["tool/p4_20_3_stage_fia_registry.py"],
            **common,
        )
        assert semantic_hold["run_expensive"] is False
        assert semantic_hold["generation_artifact_reuse"] is False
        assert semantic_hold["semantic_changed_files"] == [
            "tool/p4_20_3_stage_fia_registry.py"
        ]
        assert semantic_hold["acquisition_request_required"] is True

        semantic_authorized = decide(
            changed_files=[
                "tool/p4_20_3_stage_fia_registry.py",
                EXPLICIT_REQUEST,
            ],
            **common,
        )
        assert semantic_authorized["run_expensive"] is True
        assert semantic_authorized["acquisition_request_authorized"] is True

        stale_request = decide(changed_files=[EXPLICIT_REQUEST], **common)
        assert stale_request["run_expensive"] is False
        assert stale_request["generation_artifact_reuse"] is True
        assert stale_request["acquisition_request_authorized"] is False
        assert "FULL_ACQUISITION_REQUEST_REJECTED_SAME_GENERATION" in stale_request["reasons"]

        missing_probe = decide(
            changed_files=[EXPLICIT_REQUEST],
            **{**common, "current_source_last_modified": ""},
        )
        assert missing_probe["run_expensive"] is False
        assert missing_probe["generation_artifact_reuse"] is False
        assert missing_probe["acquisition_request_authorized"] is False
        assert missing_probe["acquisition_request_required"] is True
        assert "FULL_ACQUISITION_REQUEST_BLOCKED_SOURCE_PROBE_UNAVAILABLE" in missing_probe["reasons"]

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
