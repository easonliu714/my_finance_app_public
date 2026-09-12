#!/usr/bin/env python3
"""P4.20.3 Gate E canonical bundle-bound distribution entrypoint.

Production callers provide one strict serialized FIA+GCIS authority bundle. GCIS
workflow/artifact/closure/count provenance is derived from that validated bundle;
there is no production scalar override surface in this entrypoint.

Only the replaceable Optional Local Dataset is packaged. User-owned MerchantBrand /
LegalEntity mappings, history, corrections, and transactions are never read or
modified. Per-invoice FIA/GCIS network lookup remains forbidden.
"""
from __future__ import annotations

import argparse
import hashlib
import tempfile
from pathlib import Path

from p4_20_3_build_distribution_manifest import (
    _canonical_bytes,
    _entity,
    _load_json,
    _sha256_file,
    _write_ndjson,
    build_manifest,
    validate_manifest,
)
from p4_20_3_validate_distribution_authorities import (
    _fixture_closure,
    _fixture_source,
    build_authority_bundle,
    validate_authority_bundle,
)


def _manifest_self_hash(value: dict[str, object]) -> str:
    payload = dict(value)
    payload.pop("manifest_sha256", None)
    return hashlib.sha256(_canonical_bytes(payload)).hexdigest()


def _bundle_self_hash(value: dict[str, object]) -> str:
    payload = dict(value)
    payload.pop("authority_bundle_sha256", None)
    return hashlib.sha256(_canonical_bytes(payload)).hexdigest()


def _validate_source_bundle_binding(
    source: dict[str, object], bundle: dict[str, object]
) -> None:
    for field, label in {
        "source_authority_sha256": "SOURCE_AUTHORITY_SHA",
        "source_archive_sha256": "SOURCE_ARCHIVE_SHA",
        "source_csv_sha256": "SOURCE_CSV_SHA",
        "source_data_date": "SOURCE_DATA_DATE",
    }.items():
        if source.get(field) != bundle.get(field):
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
    source = _load_json(source_authority_path, label="SOURCE_AUTHORITY")
    _validate_source_bundle_binding(source, bundle)

    # Internal legacy primitive receives only bundle-derived values. Production
    # callers cannot override GCIS accounting or evidence independently.
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

    manifest.update(
        {
            "authority_bundle_sha256": bundle_sha,
            "gcis_full_residual_run_id": bundle["gcis_workflow_run_id"],
            "gcis_artifact_id": bundle["gcis_artifact_id"],
            "gcis_artifact_sha256": bundle["gcis_artifact_sha256"],
            "gcis_closure_sha256": bundle["gcis_closure_sha256"],
            "gcis_requested_count": bundle["gcis_seller_count"],
            "gcis_terminal_accounted_count": bundle["gcis_success_count"],
            "gcis_failure_count": bundle["gcis_failure_count"],
            "gcis_zero_silent_drop": bundle["gcis_zero_silent_drop"],
        }
    )
    manifest["manifest_sha256"] = _manifest_self_hash(manifest)
    validate_manifest(manifest, gzip_path)
    if manifest.get("authority_bundle_sha256") != bundle_sha:
        raise RuntimeError("MANIFEST_AUTHORITY_BUNDLE_SHA_MISMATCH")
    if manifest.get("git_exact_head") != bundle.get("exact_head"):
        raise RuntimeError("MANIFEST_AUTHORITY_BUNDLE_HEAD_MISMATCH")
    return manifest


def _write_summary(path: Path, canonical: Path) -> None:
    canonical_sha, canonical_bytes = _sha256_file(canonical)
    path.write_bytes(
        _canonical_bytes(
            {
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
                "validation_subset": False,
            }
        )
    )


def _attempt_build(root: Path, head: str) -> dict[str, object]:
    return build_distribution_from_authority_bundle(
        exact_head=head,
        authority_bundle_path=root / "bundle.json",
        source_authority_path=root / "source.json",
        ready_path=root / "ready.ndjson",
        enriched_path=root / "enriched.ndjson",
        canonical_path=root / "canonical.ndjson",
        canonical_summary_path=root / "summary.json",
        gzip_path=root / "registry.ndjson.gz",
    )


def self_test() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        head = "1" * 40
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
        (root / "source.json").write_bytes(_canonical_bytes(source))
        (root / "bundle.json").write_bytes(_canonical_bytes(bundle))

        ready_rows = [
            _entity("11111111", "company"),
            _entity("22222222", "branch", parent="11111111"),
        ]
        enriched_rows = [_entity("33333333", "business")]
        _write_ndjson(root / "ready.ndjson", ready_rows)
        _write_ndjson(root / "enriched.ndjson", enriched_rows)
        _write_ndjson(
            root / "canonical.ndjson",
            sorted(ready_rows + enriched_rows, key=lambda row: str(row["seller_identifier"])),
        )
        _write_summary(root / "summary.json", root / "canonical.ndjson")

        manifest = _attempt_build(root, head)
        assert manifest["authority_bundle_sha256"] == bundle["authority_bundle_sha256"]
        assert manifest["gcis_full_residual_run_id"] == 18
        assert manifest["gcis_artifact_id"] == 999
        assert manifest["gcis_artifact_sha256"] == "9" * 64
        assert manifest["gcis_closure_sha256"] == bundle["gcis_closure_sha256"]
        assert manifest["gcis_requested_count"] == manifest["gcis_terminal_accounted_count"]
        assert manifest["gcis_failure_count"] == 0

        # Content tamper with stale self-hash.
        bad = dict(bundle)
        bad["gcis_artifact_id"] = 1000
        (root / "bundle.json").write_bytes(_canonical_bytes(bad))
        try:
            _attempt_build(root, head)
            raise AssertionError("EXPECTED_BUNDLE_TAMPER_HOLD")
        except RuntimeError as exc:
            assert str(exc) == "AUTHORITY_BUNDLE_SHA_MISMATCH"

        # Re-hashed old-head bundle is still rejected by exact-head authority.
        bad = dict(bundle)
        bad["exact_head"] = "2" * 40
        bad["authority_bundle_sha256"] = _bundle_self_hash(bad)
        (root / "bundle.json").write_bytes(_canonical_bytes(bad))
        try:
            _attempt_build(root, head)
            raise AssertionError("EXPECTED_OLD_HEAD_HOLD")
        except RuntimeError as exc:
            assert str(exc) == "AUTHORITY_BUNDLE_EXACT_HEAD_MISMATCH"

        # Validly re-hashed mixed FIA generation must fail source/bundle binding.
        bad = dict(bundle)
        bad["source_archive_sha256"] = "8" * 64
        bad["authority_bundle_sha256"] = _bundle_self_hash(bad)
        (root / "bundle.json").write_bytes(_canonical_bytes(bad))
        try:
            _attempt_build(root, head)
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
