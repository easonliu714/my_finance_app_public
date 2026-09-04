#!/usr/bin/env python3
"""P4.20.3 Gate E: provenance-bound nationwide distribution manifest.

Builds a deterministic gzip artifact from the canonical NDJSON only after the
same exact Git head has complete FIA source authority and complete GCIS residual
authority. The tool independently re-hashes/counts ready, enriched and canonical
streams, rejects validation subsets / privacy leakage, and emits a manifest that
binds source date/license/provenance, entity counts, compressed artifact SHA and
installed-size disclosure.

This tool never reads user MerchantBrand / LegalEntity state and therefore cannot
modify user-owned merchant mappings/history. It only packages the replaceable
optional official-registry cache.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
import re
import tempfile
from pathlib import Path
from typing import Iterator

GIT_SHA_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SELLER_RE = re.compile(r"^\d{8}$")
ENTITY_TYPES = frozenset({"company", "business", "branch"})
CANONICAL_KEYS = frozenset({
    "record_type",
    "seller_identifier",
    "entity_type",
    "legal_name",
    "registration_status",
    "parent_seller_identifier",
    "source_dataset",
})
MAX_LINE_BYTES = 64 * 1024
SCHEMA_VERSION = 1


def _canonical_bytes(value: object) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        + "\n"
    ).encode("utf-8")


def _load_json(path: Path, *, label: str) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"{label}_JSON_INVALID") from exc
    if not isinstance(value, dict):
        raise RuntimeError(f"{label}_OBJECT_REQUIRED")
    return value


def _sha256_file(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
            size += len(chunk)
    return digest.hexdigest(), size


def _count_nonempty_lines(path: Path, *, label: str) -> int:
    count = 0
    with path.open("rb") as stream:
        for raw in stream:
            if len(raw) > MAX_LINE_BYTES:
                raise RuntimeError(f"{label}_LINE_TOO_LARGE")
            if raw.strip():
                count += 1
    return count


def _validate_source_authority(authority: dict[str, object], exact_head: str) -> None:
    if authority.get("exact_head") != exact_head:
        raise RuntimeError("SOURCE_AUTHORITY_EXACT_HEAD_MISMATCH")
    if authority.get("coverage") != "nationwide":
        raise RuntimeError("SOURCE_AUTHORITY_COVERAGE_INVALID")
    if authority.get("validation_subset") is not False:
        raise RuntimeError("SOURCE_AUTHORITY_VALIDATION_SUBSET_FORBIDDEN")
    if authority.get("responsible_person_payload_emitted") is not False:
        raise RuntimeError("SOURCE_AUTHORITY_PRIVACY_BOUNDARY_INVALID")
    if authority.get("mobile_per_invoice_network_lookup") is not False:
        raise RuntimeError("SOURCE_AUTHORITY_PER_INVOICE_NETWORK_FORBIDDEN")
    for field in (
        "source_data_date",
        "license_name",
        "license_url",
        "attribution",
        "official_dataset_identifier",
        "source_dataset",
    ):
        if not str(authority.get(field, "")).strip():
            raise RuntimeError(f"SOURCE_AUTHORITY_FIELD_REQUIRED:{field}")
    source_sha = str(authority.get("source_authority_sha256", ""))
    if not SHA256_RE.fullmatch(source_sha):
        raise RuntimeError("SOURCE_AUTHORITY_SHA_INVALID")
    payload = dict(authority)
    payload.pop("source_authority_sha256", None)
    expected = hashlib.sha256(_canonical_bytes(payload)).hexdigest()
    if source_sha != expected:
        raise RuntimeError("SOURCE_AUTHORITY_SHA_MISMATCH")


def _validate_canonical_summary(summary: dict[str, object]) -> None:
    if summary.get("gate") != "P4.20.3-E":
        raise RuntimeError("CANONICAL_SUMMARY_GATE_INVALID")
    if summary.get("validation_subset") is not False:
        raise RuntimeError("CANONICAL_SUMMARY_VALIDATION_SUBSET_FORBIDDEN")
    if summary.get("branch_parent_closure") is not True:
        raise RuntimeError("CANONICAL_SUMMARY_PARENT_CLOSURE_REQUIRED")
    if summary.get("responsible_person_payload_emitted") is not False:
        raise RuntimeError("CANONICAL_SUMMARY_PRIVACY_BOUNDARY_INVALID")
    for field in (
        "ready_entity_count",
        "enriched_entity_count",
        "canonical_entity_count",
        "company_count",
        "business_count",
        "branch_count",
        "canonical_entities_bytes",
    ):
        value = summary.get(field)
        if type(value) is not int or value < 0:
            raise RuntimeError(f"CANONICAL_SUMMARY_COUNT_INVALID:{field}")
    if not SHA256_RE.fullmatch(str(summary.get("canonical_entities_sha256", ""))):
        raise RuntimeError("CANONICAL_SUMMARY_SHA_INVALID")
    if summary["canonical_entity_count"] != (
        summary["company_count"] + summary["business_count"] + summary["branch_count"]
    ):
        raise RuntimeError("CANONICAL_SUMMARY_TYPE_PARTITION_MISMATCH")
    if summary["canonical_entity_count"] != (
        summary["ready_entity_count"] + summary["enriched_entity_count"]
    ):
        raise RuntimeError("CANONICAL_SUMMARY_INPUT_PARTITION_MISMATCH")


def _audit_canonical(path: Path) -> dict[str, int]:
    counts = {"canonical": 0, "company": 0, "business": 0, "branch": 0}
    previous = ""
    with path.open("rb") as stream:
        for line_number, raw in enumerate(stream, 1):
            if len(raw) > MAX_LINE_BYTES:
                raise RuntimeError(f"CANONICAL_LINE_TOO_LARGE:{line_number}")
            if not raw.strip():
                continue
            try:
                record = json.loads(raw)
            except json.JSONDecodeError as exc:
                raise RuntimeError(f"CANONICAL_JSON_INVALID:{line_number}") from exc
            if not isinstance(record, dict) or frozenset(record) != CANONICAL_KEYS:
                raise RuntimeError(f"CANONICAL_SURFACE_MISMATCH:{line_number}")
            if record.get("record_type") != "entity":
                raise RuntimeError(f"CANONICAL_RECORD_TYPE_INVALID:{line_number}")
            seller = str(record.get("seller_identifier", ""))
            if not SELLER_RE.fullmatch(seller):
                raise RuntimeError(f"CANONICAL_SELLER_INVALID:{line_number}")
            if previous and seller <= previous:
                raise RuntimeError(f"CANONICAL_SELLER_ORDER_INVALID:{line_number}")
            previous = seller
            entity_type = str(record.get("entity_type", ""))
            if entity_type not in ENTITY_TYPES:
                raise RuntimeError(f"CANONICAL_ENTITY_TYPE_INVALID:{line_number}")
            parent = str(record.get("parent_seller_identifier", ""))
            if entity_type == "branch":
                if not SELLER_RE.fullmatch(parent) or parent == seller:
                    raise RuntimeError(f"CANONICAL_BRANCH_PARENT_INVALID:{line_number}")
            elif parent:
                raise RuntimeError(f"CANONICAL_NON_BRANCH_PARENT_FORBIDDEN:{line_number}")
            counts["canonical"] += 1
            counts[entity_type] += 1
    return counts


def _build_deterministic_gzip(source: Path, target: Path) -> tuple[str, int]:
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = target.with_suffix(target.suffix + ".partial")
    if partial.exists():
        partial.unlink()
    try:
        with source.open("rb") as src, partial.open("wb") as raw_out:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw_out, compresslevel=9, mtime=0) as gz:
                for chunk in iter(lambda: src.read(1024 * 1024), b""):
                    gz.write(chunk)
        artifact_sha, artifact_bytes = _sha256_file(partial)
        os.replace(partial, target)
        return artifact_sha, artifact_bytes
    except Exception:
        if partial.exists():
            partial.unlink()
        raise


def build_manifest(
    *,
    exact_head: str,
    source_authority_path: Path,
    ready_path: Path,
    enriched_path: Path,
    canonical_path: Path,
    canonical_summary_path: Path,
    gzip_path: Path,
    gcis_run_id: int,
    gcis_requested_count: int,
    gcis_terminal_accounted_count: int,
    gcis_failure_count: int,
    gcis_evidence_sha256: str,
) -> dict[str, object]:
    head = exact_head.strip().lower()
    if not GIT_SHA_RE.fullmatch(head):
        raise RuntimeError("EXACT_HEAD_GIT_SHA_REQUIRED")
    if type(gcis_run_id) is not int or gcis_run_id <= 0:
        raise RuntimeError("GCIS_RUN_ID_INVALID")
    if type(gcis_requested_count) is not int or gcis_requested_count <= 0:
        raise RuntimeError("GCIS_REQUESTED_COUNT_INVALID")
    if type(gcis_terminal_accounted_count) is not int or gcis_terminal_accounted_count <= 0:
        raise RuntimeError("GCIS_TERMINAL_COUNT_INVALID")
    if type(gcis_failure_count) is not int or gcis_failure_count < 0:
        raise RuntimeError("GCIS_FAILURE_COUNT_INVALID")
    if gcis_requested_count != gcis_terminal_accounted_count:
        raise RuntimeError("GCIS_SILENT_DROP_DETECTED")
    if gcis_failure_count != 0:
        raise RuntimeError("GCIS_RESIDUAL_AUTHORITY_NOT_CLEAN")
    evidence_sha = gcis_evidence_sha256.strip().lower()
    if not SHA256_RE.fullmatch(evidence_sha):
        raise RuntimeError("GCIS_EVIDENCE_SHA_INVALID")

    source_authority = _load_json(source_authority_path, label="SOURCE_AUTHORITY")
    _validate_source_authority(source_authority, head)
    summary = _load_json(canonical_summary_path, label="CANONICAL_SUMMARY")
    _validate_canonical_summary(summary)

    ready_sha, ready_bytes = _sha256_file(ready_path)
    enriched_sha, enriched_bytes = _sha256_file(enriched_path)
    ready_count = _count_nonempty_lines(ready_path, label="READY")
    enriched_count = _count_nonempty_lines(enriched_path, label="ENRICHED")
    if ready_count != summary["ready_entity_count"]:
        raise RuntimeError("READY_ENTITY_COUNT_MISMATCH")
    if enriched_count != summary["enriched_entity_count"]:
        raise RuntimeError("ENRICHED_ENTITY_COUNT_MISMATCH")

    canonical_sha, canonical_bytes = _sha256_file(canonical_path)
    if canonical_sha != summary["canonical_entities_sha256"]:
        raise RuntimeError("CANONICAL_SHA_MISMATCH")
    if canonical_bytes != summary["canonical_entities_bytes"]:
        raise RuntimeError("CANONICAL_BYTES_MISMATCH")
    observed = _audit_canonical(canonical_path)
    expected_counts = {
        "canonical": summary["canonical_entity_count"],
        "company": summary["company_count"],
        "business": summary["business_count"],
        "branch": summary["branch_count"],
    }
    if observed != expected_counts:
        raise RuntimeError("CANONICAL_ENTITY_COUNT_MISMATCH")

    gzip_sha, gzip_bytes = _build_deterministic_gzip(canonical_path, gzip_path)
    manifest: dict[str, object] = {
        "schema_version": SCHEMA_VERSION,
        "gate": "P4.20.3-E",
        "coverage": "nationwide",
        "final_mobile_registry": True,
        "optional_local_dataset": True,
        "git_exact_head": head,
        "source_authority_sha256": source_authority["source_authority_sha256"],
        "source_dataset": source_authority["source_dataset"],
        "official_dataset_identifier": source_authority["official_dataset_identifier"],
        "source_data_date": source_authority["source_data_date"],
        "license_name": source_authority["license_name"],
        "license_url": source_authority["license_url"],
        "attribution": source_authority["attribution"],
        "gcis_full_residual_run_id": gcis_run_id,
        "gcis_requested_count": gcis_requested_count,
        "gcis_terminal_accounted_count": gcis_terminal_accounted_count,
        "gcis_failure_count": gcis_failure_count,
        "gcis_zero_silent_drop": True,
        "gcis_evidence_sha256": evidence_sha,
        "ready_entities_sha256": ready_sha,
        "ready_entities_bytes": ready_bytes,
        "ready_entity_count": ready_count,
        "enriched_entities_sha256": enriched_sha,
        "enriched_entities_bytes": enriched_bytes,
        "enriched_entity_count": enriched_count,
        "canonical_entities_sha256": canonical_sha,
        "canonical_entities_bytes": canonical_bytes,
        "canonical_entity_count": observed["canonical"],
        "company_count": observed["company"],
        "business_count": observed["business"],
        "branch_count": observed["branch"],
        "branch_parent_closure": True,
        "validation_subset": False,
        "responsible_person_payload_emitted": False,
        "mobile_per_invoice_network_lookup": False,
        "artifact_encoding": "gzip+ndjson",
        "artifact_sha256": gzip_sha,
        "artifact_bytes": gzip_bytes,
        "installed_bytes": canonical_bytes,
    }
    payload = dict(manifest)
    manifest["manifest_sha256"] = hashlib.sha256(_canonical_bytes(payload)).hexdigest()
    return manifest


def validate_manifest(manifest: dict[str, object], gzip_path: Path) -> None:
    required_true = {
        "final_mobile_registry": True,
        "optional_local_dataset": True,
        "gcis_zero_silent_drop": True,
        "branch_parent_closure": True,
    }
    required_false = {
        "validation_subset": False,
        "responsible_person_payload_emitted": False,
        "mobile_per_invoice_network_lookup": False,
    }
    for key, expected in {**required_true, **required_false}.items():
        if type(manifest.get(key)) is not bool or manifest.get(key) is not expected:
            raise RuntimeError(f"MANIFEST_BOOLEAN_INVARIANT_INVALID:{key}")
    if not GIT_SHA_RE.fullmatch(str(manifest.get("git_exact_head", ""))):
        raise RuntimeError("MANIFEST_EXACT_HEAD_INVALID")
    if manifest.get("coverage") != "nationwide" or manifest.get("artifact_encoding") != "gzip+ndjson":
        raise RuntimeError("MANIFEST_DISTRIBUTION_CONTRACT_INVALID")
    for field in ("source_data_date", "license_name", "license_url", "attribution"):
        if not str(manifest.get(field, "")).strip():
            raise RuntimeError(f"MANIFEST_PROVENANCE_REQUIRED:{field}")
    if manifest.get("gcis_requested_count") != manifest.get("gcis_terminal_accounted_count"):
        raise RuntimeError("MANIFEST_GCIS_ACCOUNTING_MISMATCH")
    if manifest.get("gcis_failure_count") != 0:
        raise RuntimeError("MANIFEST_GCIS_FAILURES_PRESENT")
    if manifest.get("canonical_entity_count") != (
        manifest.get("company_count", -1)
        + manifest.get("business_count", -1)
        + manifest.get("branch_count", -1)
    ):
        raise RuntimeError("MANIFEST_ENTITY_PARTITION_MISMATCH")
    artifact_sha, artifact_bytes = _sha256_file(gzip_path)
    if artifact_sha != manifest.get("artifact_sha256") or artifact_bytes != manifest.get("artifact_bytes"):
        raise RuntimeError("MANIFEST_ARTIFACT_MISMATCH")
    payload = dict(manifest)
    actual_manifest_sha = str(payload.pop("manifest_sha256", ""))
    expected_manifest_sha = hashlib.sha256(_canonical_bytes(payload)).hexdigest()
    if actual_manifest_sha != expected_manifest_sha:
        raise RuntimeError("MANIFEST_SHA_MISMATCH")


def _write_ndjson(path: Path, rows: list[dict[str, object]]) -> None:
    path.write_bytes(b"".join(_canonical_bytes(row) for row in rows))


def _entity(seller: str, entity_type: str, *, parent: str = "") -> dict[str, object]:
    return {
        "record_type": "entity",
        "seller_identifier": seller,
        "entity_type": entity_type,
        "legal_name": seller,
        "registration_status": "active",
        "parent_seller_identifier": parent,
        "source_dataset": "FIXTURE",
    }


def _source_authority(head: str) -> dict[str, object]:
    payload: dict[str, object] = {
        "schema_version": 1,
        "exact_head": head,
        "coverage": "nationwide",
        "source_dataset": "MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY",
        "official_dataset_identifier": "data.gov.tw/dataset/9400",
        "dataset_name": "全國營業(稅籍)登記資料集",
        "dataset_page_url": "https://data.gov.tw/dataset/9400",
        "archive_url": "https://eip.fia.gov.tw/data/BGMOPEN1.zip",
        "provider": "財政部財政資訊中心",
        "update_cadence": "daily",
        "source_last_modified": "Tue, 01 Sep 2026 21:11:34 GMT",
        "source_data_date": "2026-09-01",
        "source_archive_sha256": "b" * 64,
        "source_archive_bytes": 100,
        "source_row_count": 3,
        "license_name": "政府資料開放授權條款-第1版",
        "license_url": "https://data.gov.tw/license",
        "attribution": "財政部財政資訊中心 2026 全國營業(稅籍)登記資料集",
        "validation_subset": False,
        "responsible_person_payload_emitted": False,
        "mobile_per_invoice_network_lookup": False,
    }
    return {**payload, "source_authority_sha256": hashlib.sha256(_canonical_bytes(payload)).hexdigest()}


def self_test() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        head = "a" * 40
        source = root / "source.json"
        ready = root / "ready.ndjson"
        enriched = root / "enriched.ndjson"
        canonical = root / "canonical.ndjson"
        summary = root / "summary.json"
        artifact = root / "registry.ndjson.gz"
        manifest_path = root / "manifest.json"

        source.write_bytes(_canonical_bytes(_source_authority(head)))
        ready_rows = [_entity("11111111", "company"), _entity("22222222", "branch", parent="11111111")]
        enriched_rows = [_entity("33333333", "business")]
        _write_ndjson(ready, ready_rows)
        _write_ndjson(enriched, enriched_rows)
        canonical_rows = sorted(ready_rows + enriched_rows, key=lambda row: str(row["seller_identifier"]))
        _write_ndjson(canonical, canonical_rows)
        canonical_sha, canonical_bytes = _sha256_file(canonical)
        summary_value = {
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
        summary.write_bytes(_canonical_bytes(summary_value))

        kwargs = dict(
            exact_head=head,
            source_authority_path=source,
            ready_path=ready,
            enriched_path=enriched,
            canonical_path=canonical,
            canonical_summary_path=summary,
            gzip_path=artifact,
            gcis_run_id=13,
            gcis_requested_count=15760,
            gcis_terminal_accounted_count=15760,
            gcis_failure_count=0,
            gcis_evidence_sha256="c" * 64,
        )
        manifest = build_manifest(**kwargs)
        validate_manifest(manifest, artifact)
        manifest_path.write_bytes(_canonical_bytes(manifest))
        first_artifact = artifact.read_bytes()
        second = build_manifest(**kwargs)
        assert artifact.read_bytes() == first_artifact
        assert second["artifact_sha256"] == manifest["artifact_sha256"]
        assert second["manifest_sha256"] == manifest["manifest_sha256"]

        bad_source = _source_authority("d" * 40)
        source.write_bytes(_canonical_bytes(bad_source))
        try:
            build_manifest(**kwargs)
            raise AssertionError("EXPECTED_EXACT_HEAD_HOLD")
        except RuntimeError as exc:
            assert str(exc) == "SOURCE_AUTHORITY_EXACT_HEAD_MISMATCH"
        source.write_bytes(_canonical_bytes(_source_authority(head)))

        bad_summary = dict(summary_value)
        bad_summary["validation_subset"] = True
        summary.write_bytes(_canonical_bytes(bad_summary))
        try:
            build_manifest(**kwargs)
            raise AssertionError("EXPECTED_VALIDATION_SUBSET_HOLD")
        except RuntimeError as exc:
            assert str(exc) == "CANONICAL_SUMMARY_VALIDATION_SUBSET_FORBIDDEN"
        summary.write_bytes(_canonical_bytes(summary_value))

        try:
            build_manifest(**{**kwargs, "gcis_terminal_accounted_count": 15759})
            raise AssertionError("EXPECTED_GCIS_SILENT_DROP_HOLD")
        except RuntimeError as exc:
            assert str(exc) == "GCIS_SILENT_DROP_DETECTED"

        tampered = bytearray(artifact.read_bytes())
        tampered[-1] ^= 1
        artifact.write_bytes(tampered)
        try:
            validate_manifest(manifest, artifact)
            raise AssertionError("EXPECTED_ARTIFACT_MISMATCH_HOLD")
        except RuntimeError as exc:
            assert str(exc) == "MANIFEST_ARTIFACT_MISMATCH"

    print("P4_20_3_DISTRIBUTION_MANIFEST_SELFTEST=PASS")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--exact-head")
    parser.add_argument("--source-authority", type=Path)
    parser.add_argument("--ready", type=Path)
    parser.add_argument("--enriched", type=Path)
    parser.add_argument("--canonical", type=Path)
    parser.add_argument("--canonical-summary", type=Path)
    parser.add_argument("--gzip-output", type=Path)
    parser.add_argument("--manifest-output", type=Path)
    parser.add_argument("--gcis-run-id", type=int)
    parser.add_argument("--gcis-requested-count", type=int)
    parser.add_argument("--gcis-terminal-accounted-count", type=int)
    parser.add_argument("--gcis-failure-count", type=int)
    parser.add_argument("--gcis-evidence-sha256")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return 0

    required = (
        args.exact_head,
        args.source_authority,
        args.ready,
        args.enriched,
        args.canonical,
        args.canonical_summary,
        args.gzip_output,
        args.manifest_output,
        args.gcis_run_id,
        args.gcis_requested_count,
        args.gcis_terminal_accounted_count,
        args.gcis_failure_count,
        args.gcis_evidence_sha256,
    )
    if any(value is None for value in required):
        parser.error("production mode requires all provenance and artifact arguments")

    manifest = build_manifest(
        exact_head=args.exact_head,
        source_authority_path=args.source_authority,
        ready_path=args.ready,
        enriched_path=args.enriched,
        canonical_path=args.canonical,
        canonical_summary_path=args.canonical_summary,
        gzip_path=args.gzip_output,
        gcis_run_id=args.gcis_run_id,
        gcis_requested_count=args.gcis_requested_count,
        gcis_terminal_accounted_count=args.gcis_terminal_accounted_count,
        gcis_failure_count=args.gcis_failure_count,
        gcis_evidence_sha256=args.gcis_evidence_sha256,
    )
    validate_manifest(manifest, args.gzip_output)
    args.manifest_output.parent.mkdir(parents=True, exist_ok=True)
    args.manifest_output.write_bytes(_canonical_bytes(manifest))
    print(f"P4_20_3_DISTRIBUTION_MANIFEST_SHA256={manifest['manifest_sha256']}")
    print(f"P4_20_3_DISTRIBUTION_ARTIFACT_SHA256={manifest['artifact_sha256']}")
    print("P4_20_3_DISTRIBUTION_MANIFEST=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
