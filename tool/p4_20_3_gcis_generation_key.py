#!/usr/bin/env python3
"""P4.20.3 content-addressed GCIS acquisition generation authority.

The generation key intentionally excludes Git commit/head identity. It changes only
when the official FIA source generation or acquisition/staging semantics change.
This allows downstream-only PR heads to re-verify and reuse frozen GCIS evidence
without repeating the 15k+ seller acquisition.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1
POLICY_VERSION = "p4.20.3-gcis-generation-policy-v1"


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _require_sha256(value: str, field: str) -> str:
    value = value.strip().lower()
    if len(value) != 64 or any(ch not in "0123456789abcdef" for ch in value):
        raise ValueError(f"{field} must be a lowercase/uppercase SHA-256 hex digest")
    return value


@dataclass(frozen=True)
class GenerationAuthority:
    schema_version: int
    policy_version: str
    fia_source_archive_sha256: str
    fia_source_last_modified: str
    staging_tool_sha256: str
    acquisition_tool_sha256: str
    staging_semantic_version: str
    acquisition_semantic_version: str
    evidence_schema_version: str
    privacy_policy_version: str
    shard_policy: str

    def canonical_payload(self) -> bytes:
        return json.dumps(
            asdict(self),
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")

    def generation_key(self) -> str:
        return hashlib.sha256(self.canonical_payload()).hexdigest()


def build_authority(args: argparse.Namespace) -> GenerationAuthority:
    if not args.fia_source_last_modified.strip():
        raise ValueError("fia_source_last_modified must be non-empty")
    return GenerationAuthority(
        schema_version=SCHEMA_VERSION,
        policy_version=POLICY_VERSION,
        fia_source_archive_sha256=_require_sha256(
            args.fia_source_archive_sha256, "fia_source_archive_sha256"
        ),
        fia_source_last_modified=args.fia_source_last_modified.strip(),
        staging_tool_sha256=_sha256_file(Path(args.staging_tool)),
        acquisition_tool_sha256=_sha256_file(Path(args.acquisition_tool)),
        staging_semantic_version=args.staging_semantic_version.strip(),
        acquisition_semantic_version=args.acquisition_semantic_version.strip(),
        evidence_schema_version=args.evidence_schema_version.strip(),
        privacy_policy_version=args.privacy_policy_version.strip(),
        shard_policy=args.shard_policy.strip(),
    )


def _self_test() -> None:
    base = {
        "schema_version": SCHEMA_VERSION,
        "policy_version": POLICY_VERSION,
        "fia_source_archive_sha256": "a" * 64,
        "fia_source_last_modified": "Tue, 01 Sep 2026 21:11:34 GMT",
        "staging_tool_sha256": "b" * 64,
        "acquisition_tool_sha256": "c" * 64,
        "staging_semantic_version": "stage-v1",
        "acquisition_semantic_version": "acquire-v1",
        "evidence_schema_version": "4",
        "privacy_policy_version": "privacy-v1-no-responsible-person",
        "shard_policy": "sorted_unique_sellers[index::8]",
    }
    first = GenerationAuthority(**base)
    second = GenerationAuthority(**dict(reversed(list(base.items()))))
    assert first.generation_key() == second.generation_key()

    changed_source = GenerationAuthority(**{**base, "fia_source_archive_sha256": "d" * 64})
    changed_tool = GenerationAuthority(**{**base, "acquisition_tool_sha256": "e" * 64})
    changed_policy = GenerationAuthority(**{**base, "privacy_policy_version": "privacy-v2"})
    assert first.generation_key() != changed_source.generation_key()
    assert first.generation_key() != changed_tool.generation_key()
    assert first.generation_key() != changed_policy.generation_key()

    # Exact PR head is deliberately absent: downstream-only commits must not
    # invalidate reusable official evidence when source + semantics are unchanged.
    assert "exact_head" not in asdict(first)
    assert "commit_sha" not in asdict(first)
    print("P4_20_3_GCIS_GENERATION_KEY_SELF_TEST=PASS")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--fia-source-archive-sha256")
    parser.add_argument("--fia-source-last-modified")
    parser.add_argument("--staging-tool", default="tool/p4_20_3_stage_fia_registry.py")
    parser.add_argument("--acquisition-tool", default="tool/p4_20_3_acquire_gcis_registration_type.py")
    parser.add_argument("--staging-semantic-version", default="p4.20.3-stage-v1")
    parser.add_argument("--acquisition-semantic-version", default="p4.20.3-gcis-acquire-v1")
    parser.add_argument("--evidence-schema-version", default="4")
    parser.add_argument("--privacy-policy-version", default="no-responsible-person-v1")
    parser.add_argument("--shard-policy", default="sorted_unique_sellers[index::8]")
    parser.add_argument("--output")
    args = parser.parse_args()

    if args.self_test:
        _self_test()
        return 0

    required = (args.fia_source_archive_sha256, args.fia_source_last_modified)
    if not all(required):
        parser.error("--fia-source-archive-sha256 and --fia-source-last-modified are required")

    authority = build_authority(args)
    payload: dict[str, Any] = asdict(authority)
    payload["generation_key"] = authority.generation_key()
    text = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
    else:
        print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
