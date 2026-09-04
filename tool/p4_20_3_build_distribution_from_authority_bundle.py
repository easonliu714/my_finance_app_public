#!/usr/bin/env python3
"""P4.20.3 Gate E canonical production manifest entrypoint.

Consumes a serialized, strict-validated FIA+GCIS authority bundle and derives all
GCIS provenance from it. The legacy scalar builder remains an internal packaging
primitive only; production callers must use this entrypoint so workflow/artifact/
closure identity and the authority bundle self-hash are bound into the manifest.

The tool packages only the replaceable Optional Local Dataset. It never reads or
modifies user-owned MerchantBrand / LegalEntity mappings, history, corrections,
or transactions, and it never enables per-invoice FIA/GCIS network lookup.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import tempfile
from pathlib import Path

from p4_20_3_build_distribution_manifest import (
    _canonical_bytes,
    _load_json,
    _sha256_file,
    _source_authority,
    _write_ndjson,
    _entity,
    build_manifest,
    validate_manifest,
)
from p4_20_3_validate_distribution_authorities import (
    build_authority_bundle,
    validate_authority_bundle,
    _fixture_closure,
    _fixture_source,
)


def _manifest_self_hash(manifest: dict[str, object]) -> str:
    payload = dict(manifest)
    payload.pop("manifest_sha256", None)
    return hashlib.sha256(_canonical_bytes(payload)).hexdigest()


def _validate_source_bundle_binding(
    source_authority: dict[str, object], bundle: dict[str, object]
) -> None:
    checks = {
        "source_authority_sha256": "SOURCE_AUTHORITY_SHA",
        "source_archive_sha256": "SOURCE_ARCHIVE_SHA",
        "source_csv_sha256": "SOURCE_CSV_SHA",
        "source_data_date": "SOURCE_DATA_DATE",
    }
    for field, label in checks.items():
        if source_authority.get(field) != bundle.get(field):
            raise RuntimeError(f"AUTHORITY_BUNDLE_{label}_MISMATCH")


def build_distribution_from_authority_bundle(
    *,
    exact_head: str,
    authority_bundle_path: Path,
    source_authority_path: Path,
    ready_path: Path,
    enriched_path: Path,
    canonical_path: Path,
    canonical_summary_path: Path,
    gzip_path: Path,
) -> dict[str, object]:
    bundle = _load_json(authority_bundle_path, label="AUTHORITY_BUNDLE")
    bundle_sha = validate_authority_bundle(bundle, exact_head)
    source_authority = _load_json(source_authority_path, label="SOURCE_AUTHORITY")
    _validate_source_bundle_binding(source_authority, bundle)

    # The legacy builder is deliberately called only with values derived from the
    # already validated bundle; production callers have no scalar override surface.
    manifest = build_manifest(
        exact_head=exact_head,
        source_authority_path=source_authority_path,
        ready_path=ready_path,
        enriched_path=enriched_path,
        canonical_path=canonical_path,
        canonical_summary_path=canonical_summary_path,
        gzip_path=gzip_path,
        gcis_run_id=int(bundle["gcis_workflow_run_id"]),
        gcis_requested_count=int(bundle["gcis_seller_count"]),
        gcis_terminal_accounted_count=int(bundle["gcis_success_count"]),
        gcis_failure_count=int(bundle["gcis_failure_count"]),
        gcis_evidence_sha256=str(bundle["gcis_closure_sha256"]),
    )

    manifest["authority_bundle_sha256"] = bundle_sha
    manifest["gcis_full_residual_run_id"] = bundle["gcis_workflow_run_id"]
    manifest["gcis_artifact_id"] = bundle["gcis_artifact_id"]
    manifest["gcis_artifact_sha256"] = bundle["gcis_artifact_sha256"]
    manifest["gcis_closure_sha256"] = bundle["gcis_closure_sha256"]
    manifest["gcis_requested_count"] = bundle["gcis_seller_count"]
    manifest["gcis_terminal_accounted_count"] = bundle["gcis_success_count"]
    manifest["gcis_failure_count"] = bundle["gcis_failure_count"]
    manifest["gcis_zero_silent_drop"] = bundle["gcis_zero_silent_drop"]
    manifest["manifest_sha256"] = _manifest_self_hash(manifest)

    validate_manifest(manifest, gzip_path)
    if manifest.get("authority_bundle_sha256") != bundle_sha:
        raise RuntimeError("MANIFEST_AUTHORITY_BUNDLE_SHA_MISMATCH")
    if manifest.get("git_exact_head") != bundle.get("exact_head"):
        raise RuntimeError("MANIFEST_AUTHORITY_BUNDLE_HEAD_MISMATCH")
    return manifest


def _write_fixture_summary(
    path: Path, canonical_path: Path, *, validation_subset: bool = False
) -> None:
    canonical_sha, canonical_bytes = _sha256_file(canonical_path)
    value = {
        "schema_version": 1,
        "gate": "P4.20.3-E",
        "coverage": "nationwide_candidate",
        "final_mobile_registry": False,
        "canonical_uniqueness_key": "seller_identifier",
        "ready_entity_count": 2,
        "enriched_entity_count": 1,
        "canonical_entity_count": 3,
        "company_count": 1,
        "business_count": 1,
        "branch_count": 1,
        "canonical_entities_sha256": canonical_sha,
        "canonical_entities_bytes": canonical_bytes,
        "branch_parent_closure": True,
        "responsible_person_payload_emitted": False,
        "validation_subset": validation_subset,
    }
    path.write_bytes(_canonical_bytes(value))


def self_test() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        head = "1" * 40
        source_path = root / "source.json"
        bundle_path = root / "bundle.json"
        ready = root / "ready.ndjson"
        enriched = root / "enriched.ndjson"
        canonical = root / "canonical.ndjson"
        summary = root / "summary.json"
        gzip_path = root / "registry.ndjson.gz"

        # Use the strict authority validator fixtures because they contain the
        # complete replay-critical FIA fields required by the bundle contract.
        source = _fixture_source(head)
        closure = _fixture_closure(head, source)
        bundle = build_authority_bundle(
            exact_head=head,
            source=source,
            closure=closure,
            gcis_workflow_run_id=18,
            gcis_artifact_id=999,
            gcis_artifact_sha256="9" * 64,
        )
        source_path.write_bytes(_canonical_bytes(source))
        bundle_path.write_bytes(_canonical_bytes(bundle))

        ready_rows = [
            _entity("11111111", "company"),
            _entity("22222222", "branch", parent="11111111"),
        ]
        enriched_rows = [_entity("33333333", "business")]
        _write_ndjson(ready, ready_rows)
        _write_ndjson(enriched, enriched_rows)
        _write_ndjson(
            canonical,
            sorted(ready_rows + enriched_rows, key=lambda row: str(row["seller_identifier"])),
        )
        _write_fixture_summary(summary, canonical)

        manifest = build_distribution_from_authority_bundle(
            exact_head=head,
            authority_bundle_path=bundle_path,
            source_authority_path=source_path,
            ready_path=ready,
            enriched_path=enriched,
            canonical_path=canonical,
            canonical_summary_path=summary,
            gzip_path=gzip_path,
        )
        assert manifest["authority_bundle_sha256"] == bundle["authority_bundle_sha256"]
        assert manifest["gcis_full_residual_run_id"] == 18
        assert manifest["gcis_artifact_id"] == 999
        assert manifest["gcis_artifact_sha256"] == "9" * 64
        assert manifest["gcis_closure_sha256"] == bundle["gcis_closure_sha256"]
        assert manifest["gcis_requested_count"] == bundle["gcis_seller_count"]
        assert manifest["gcis_terminal_accounted_count"] == bundle["gcis_success_count"]

        # Tamper + stale bundle SHA must fail closed.
        tampered = dict(bundle)
        tampered["gcis_artifact_id"] = int(tampered["gcis_artifact_id"]) + 1
        bundle_path.write_bytes(_canonical_bytes(tampered))
        try:
            build_distribution_from_authority_bundle(
                exact_head=head,
                authority_bundle_path=bundle_path,
                source_authority_path=source_path,
                ready_path=ready,
                enriched_path=enriched,
                canonical_path=canonical,
                canonical_summary_path=summary,
                gzip_path=gzip_path,
            )
            raise AssertionError("EXPECTED_BUNDLE_TAMPER_HOLD")
        except RuntimeError as exc:
            assert str(exc) == "AUTHORITY_BUNDLE_SHA_MISMATCH"

        # Re-signed old-head bundle must still be rejected by exact-head gate.
        old = dict(bundle)
        old["exact_head"] = "2" * 40
        old["authority_bundle_sha256"] = _manifest_self_hash(old)
        bundle_path.write_bytes(_canonical_bytes(old))
        try:
            build_distribution_from_authority_bundle(
                exact_head=head,
                authority_bundle_path=bundle_path,
                source_authority_path=source_path,
                ready_path=ready,
                enriched_path=enriched,
                canonical_path=canonical,
                canonical_summary_path=summary,
                gzip_path=gzip_path,
            )
            raise AssertionError("EXPECTED_OLD_HEAD_HOLD")
        except RuntimeError as exc:
            assert str(exc) == "AUTHORITY_BUNDLE_EXACT_HEAD_MISMATCH"

        # A validly re-hashed bundle with mixed FIA generation must be rejected.
        mixed = dict(bundle)
        mixed["source_archive_sha256"] = "8" * 64
        mixed["authority_bundle_sha256"] = _manifest_self_hash(mixed)
        bundle_path.write_bytes(_canonical_bytes(mixed))
        try:
            build_distribution_from_authority_bundle(
                exact_head=head,
                authority_bundle_path=bundle_path,
                source_authority_path=source_path,
                ready_path=ready,
                enriched_path=enriched,
                canonical_path=canonical,
                canonical_summary_path=summary,
                gzip_path=gzip_path,
            )
            raise AssertionError("EXPECTED_MIXED_GENERATION_HOLD")
        except RuntimeError as exc:
            assert str(exc) == "AUTHORITY_BUNDLE_SOURCE_ARCHIVE_SHA_MISMATCH"

    print("P4_20_3_BUNDLE_BOUND_DISTRIBUTION_SELFTEST=PASS")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--exact-head")
    parser.add_argument("--authority-bundle", type=Path)
    parser.add_argument("--source-authority", type=Path)
    parser.add_argument("--ready", type=Path)
    parser.add_argument("--enriched", type=Path)
    parser.add_argument("--canonical", type=Path)
    parser.add_argument("--canonical-summary", type=Path)
    parser.add_argument("--gzip-output", type=Path)
    parser.add_argument("--manifest-output", type=Path)
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return 0

    required = (
        args.exact_head,
        args.authority_bundle,
        args.source_authority,
        args.ready,
        args.enriched,
        args.canonical,
        args.canonical_summary,
        args.gzip_output,
        args.manifest_output,
    )
    if any(value is None for value in required):
        parser.error("production mode requires exact head, authority bundle, provenance, and artifact paths")

    manifest = build_distribution_from_authority_bundle(
        exact_head=args.exact_head,
        authority_bundle_path=args.authority_bundle,
        source_authority_path=args.source_authority,
        ready_path=args.ready,
        enriched_path=args.enriched,
        canonical_path=args.canonical,
        canonical_summary_path=args.canonical_summary,
        gzip_path=args.gzip_output,
    )
    args.manifest_output.parent.mkdir(parents=True, exist_ok=True)
    args.manifest_output.write_bytes(_canonical_bytes(manifest))
    print(f"P4_20_3_AUTHORITY_BUNDLE_SHA256={manifest['authority_bundle_sha256']}")
    print(f"P4_20_3_DISTRIBUTION_MANIFEST_SHA256={manifest['manifest_sha256']}")
    print(f"P4_20_3_DISTRIBUTION_ARTIFACT_SHA256={manifest['artifact_sha256']}")
    print("P4_20_3_BUNDLE_BOUND_DISTRIBUTION=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
