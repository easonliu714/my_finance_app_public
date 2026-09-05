#!/usr/bin/env python3
"""P4.20.3 Gate E authority-bundle validator.

Validates the FIA replay authority and GCIS full-residual closure as one exact-head,
privacy-reduced production provenance bundle. This module is deliberately independent
of handset/user MerchantBrand and LegalEntity state.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

GIT_SHA_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SOURCE_REQUIRED_TEXT = (
    "source_data_date", "license_name", "license_url", "attribution",
    "official_dataset_identifier", "source_dataset", "archive_url",
    "source_last_modified", "csv_member",
)
SOURCE_REQUIRED_SHA = ("source_archive_sha256", "source_csv_sha256")
SOURCE_REQUIRED_POSITIVE_INT = (
    "source_archive_bytes", "source_csv_bytes", "source_row_count",
    "acquisition_run_id", "evidence_artifact_id",
)
BUNDLE_KEYS = frozenset({
    "schema_version", "gate", "exact_head", "validation_subset",
    "responsible_person_payload_emitted", "mobile_per_invoice_network_lookup",
    "source_authority_sha256", "source_archive_sha256", "source_csv_sha256",
    "source_data_date", "gcis_workflow_run_id", "gcis_closure_sha256",
    "gcis_artifact_id", "gcis_artifact_sha256", "gcis_seller_count",
    "gcis_success_count", "gcis_failure_count", "gcis_zero_silent_drop",
    "authority_bundle_sha256",
})


def _canonical_bytes(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def _load(path: Path, label: str) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"{label}_JSON_INVALID") from exc
    if not isinstance(value, dict):
        raise RuntimeError(f"{label}_OBJECT_REQUIRED")
    return value


def _self_hash(value: dict[str, object], field: str, label: str) -> str:
    actual = str(value.get(field, "")).lower()
    if not SHA256_RE.fullmatch(actual):
        raise RuntimeError(f"{label}_SHA_INVALID")
    payload = dict(value)
    payload.pop(field, None)
    expected = hashlib.sha256(_canonical_bytes(payload)).hexdigest()
    if actual != expected:
        raise RuntimeError(f"{label}_SHA_MISMATCH")
    return actual


def validate_source_authority(source: dict[str, object], exact_head: str) -> str:
    if source.get("exact_head") != exact_head:
        raise RuntimeError("SOURCE_AUTHORITY_EXACT_HEAD_MISMATCH")
    if source.get("coverage") != "nationwide":
        raise RuntimeError("SOURCE_AUTHORITY_COVERAGE_INVALID")
    if source.get("validation_subset") is not False:
        raise RuntimeError("SOURCE_AUTHORITY_VALIDATION_SUBSET_FORBIDDEN")
    if source.get("responsible_person_payload_emitted") is not False:
        raise RuntimeError("SOURCE_AUTHORITY_PRIVACY_BOUNDARY_INVALID")
    if source.get("mobile_per_invoice_network_lookup") is not False:
        raise RuntimeError("SOURCE_AUTHORITY_PER_INVOICE_NETWORK_FORBIDDEN")
    for field in SOURCE_REQUIRED_TEXT:
        if not str(source.get(field, "")).strip():
            raise RuntimeError(f"SOURCE_AUTHORITY_FIELD_REQUIRED:{field}")
    for field in SOURCE_REQUIRED_SHA:
        if not SHA256_RE.fullmatch(str(source.get(field, "")).lower()):
            raise RuntimeError(f"SOURCE_AUTHORITY_SHA_FIELD_INVALID:{field}")
    for field in SOURCE_REQUIRED_POSITIVE_INT:
        value = source.get(field)
        if type(value) is not int or value <= 0:
            raise RuntimeError(f"SOURCE_AUTHORITY_INT_FIELD_INVALID:{field}")
    artifact_sha = str(source.get("evidence_artifact_sha256", "")).lower()
    if not SHA256_RE.fullmatch(artifact_sha):
        raise RuntimeError("SOURCE_AUTHORITY_EVIDENCE_SHA_INVALID")
    return _self_hash(source, "source_authority_sha256", "SOURCE_AUTHORITY")


def validate_gcis_closure(closure: dict[str, object], exact_head: str, *, workflow_run_id: int, artifact_id: int, artifact_sha256: str) -> str:
    if closure.get("exact_head") != exact_head:
        raise RuntimeError("GCIS_CLOSURE_EXACT_HEAD_MISMATCH")
    if closure.get("gate") != "P4.20.3-D-full-residual-acquisition-closure":
        raise RuntimeError("GCIS_CLOSURE_GATE_INVALID")
    if closure.get("validation_subset") is not False:
        raise RuntimeError("GCIS_CLOSURE_VALIDATION_SUBSET_FORBIDDEN")
    if closure.get("responsible_person_payload_emitted") is not False:
        raise RuntimeError("GCIS_CLOSURE_PRIVACY_BOUNDARY_INVALID")
    if closure.get("mobile_per_invoice_network_lookup") is not False:
        raise RuntimeError("GCIS_CLOSURE_PER_INVOICE_NETWORK_FORBIDDEN")
    if closure.get("final_mobile_registry") is not False:
        raise RuntimeError("GCIS_CLOSURE_MUST_NOT_SELF_PROMOTE_FINAL")
    for field in ("source_archive_sha256", "source_authority_sha256", "residual_payload_sha256", "seller_set_sha256", "globally_sorted_combined_evidence_sha256"):
        if not SHA256_RE.fullmatch(str(closure.get(field, "")).lower()):
            raise RuntimeError(f"GCIS_CLOSURE_SHA_FIELD_INVALID:{field}")
    seller_count = closure.get("seller_count")
    success_count = closure.get("total_success_count")
    failure_count = closure.get("total_failure_count")
    shard_count = closure.get("shard_count")
    if type(seller_count) is not int or seller_count <= 0:
        raise RuntimeError("GCIS_CLOSURE_SELLER_COUNT_INVALID")
    if type(success_count) is not int or success_count < 0:
        raise RuntimeError("GCIS_CLOSURE_SUCCESS_COUNT_INVALID")
    if type(failure_count) is not int or failure_count < 0:
        raise RuntimeError("GCIS_CLOSURE_FAILURE_COUNT_INVALID")
    if type(shard_count) is not int or shard_count <= 0:
        raise RuntimeError("GCIS_CLOSURE_SHARD_COUNT_INVALID")
    if failure_count != 0:
        raise RuntimeError("GCIS_CLOSURE_FAILURES_PRESENT")
    if success_count != seller_count:
        raise RuntimeError("GCIS_CLOSURE_SILENT_DROP_DETECTED")
    if type(workflow_run_id) is not int or workflow_run_id <= 0:
        raise RuntimeError("GCIS_WORKFLOW_RUN_ID_INVALID")
    if type(artifact_id) is not int or artifact_id <= 0:
        raise RuntimeError("GCIS_ARTIFACT_ID_INVALID")
    if not SHA256_RE.fullmatch(artifact_sha256.lower()):
        raise RuntimeError("GCIS_ARTIFACT_SHA_INVALID")
    return hashlib.sha256(_canonical_bytes(closure)).hexdigest()


def build_authority_bundle(*, exact_head: str, source: dict[str, object], closure: dict[str, object], gcis_workflow_run_id: int, gcis_artifact_id: int, gcis_artifact_sha256: str) -> dict[str, object]:
    head = exact_head.strip().lower()
    if not GIT_SHA_RE.fullmatch(head):
        raise RuntimeError("EXACT_HEAD_GIT_SHA_REQUIRED")
    source_sha = validate_source_authority(source, head)
    closure_sha = validate_gcis_closure(closure, head, workflow_run_id=gcis_workflow_run_id, artifact_id=gcis_artifact_id, artifact_sha256=gcis_artifact_sha256)
    if str(closure.get("source_authority_sha256", "")) != source_sha:
        raise RuntimeError("GCIS_SOURCE_AUTHORITY_CROSS_GENERATION_MISMATCH")
    if str(closure.get("source_archive_sha256", "")) != str(source.get("source_archive_sha256", "")):
        raise RuntimeError("GCIS_SOURCE_ARCHIVE_CROSS_GENERATION_MISMATCH")
    bundle: dict[str, object] = {
        "schema_version": 1, "gate": "P4.20.3-E-authority-bundle", "exact_head": head,
        "validation_subset": False, "responsible_person_payload_emitted": False,
        "mobile_per_invoice_network_lookup": False,
        "source_authority_sha256": source_sha, "source_archive_sha256": source["source_archive_sha256"],
        "source_csv_sha256": source["source_csv_sha256"], "source_data_date": source["source_data_date"],
        "gcis_workflow_run_id": gcis_workflow_run_id, "gcis_closure_sha256": closure_sha,
        "gcis_artifact_id": gcis_artifact_id, "gcis_artifact_sha256": gcis_artifact_sha256.lower(),
        "gcis_seller_count": closure["seller_count"], "gcis_success_count": closure["total_success_count"],
        "gcis_failure_count": closure["total_failure_count"], "gcis_zero_silent_drop": True,
    }
    bundle["authority_bundle_sha256"] = hashlib.sha256(_canonical_bytes(bundle)).hexdigest()
    return bundle


def validate_authority_bundle(bundle: dict[str, object], exact_head: str) -> str:
    """Strict consumer-side validation for a serialized Gate E authority bundle."""
    head = exact_head.strip().lower()
    if not GIT_SHA_RE.fullmatch(head):
        raise RuntimeError("EXACT_HEAD_GIT_SHA_REQUIRED")
    keys = frozenset(bundle)
    if keys != BUNDLE_KEYS:
        missing = sorted(BUNDLE_KEYS - keys)
        unknown = sorted(keys - BUNDLE_KEYS)
        if missing:
            raise RuntimeError(f"AUTHORITY_BUNDLE_FIELD_MISSING:{missing[0]}")
        raise RuntimeError(f"AUTHORITY_BUNDLE_FIELD_UNKNOWN:{unknown[0]}")
    if bundle.get("schema_version") != 1 or type(bundle.get("schema_version")) is not int:
        raise RuntimeError("AUTHORITY_BUNDLE_SCHEMA_INVALID")
    if bundle.get("gate") != "P4.20.3-E-authority-bundle":
        raise RuntimeError("AUTHORITY_BUNDLE_GATE_INVALID")
    if bundle.get("exact_head") != head:
        raise RuntimeError("AUTHORITY_BUNDLE_EXACT_HEAD_MISMATCH")
    for field in ("validation_subset", "responsible_person_payload_emitted", "mobile_per_invoice_network_lookup"):
        if bundle.get(field) is not False:
            raise RuntimeError(f"AUTHORITY_BUNDLE_BOOLEAN_INVARIANT_INVALID:{field}")
    if bundle.get("gcis_zero_silent_drop") is not True:
        raise RuntimeError("AUTHORITY_BUNDLE_ZERO_SILENT_DROP_REQUIRED")
    for field in ("source_authority_sha256", "source_archive_sha256", "source_csv_sha256", "gcis_closure_sha256", "gcis_artifact_sha256"):
        if not SHA256_RE.fullmatch(str(bundle.get(field, "")).lower()):
            raise RuntimeError(f"AUTHORITY_BUNDLE_SHA_FIELD_INVALID:{field}")
    for field in ("gcis_workflow_run_id", "gcis_artifact_id", "gcis_seller_count", "gcis_success_count"):
        value = bundle.get(field)
        if type(value) is not int or value <= 0:
            raise RuntimeError(f"AUTHORITY_BUNDLE_INT_FIELD_INVALID:{field}")
    failure_count = bundle.get("gcis_failure_count")
    if type(failure_count) is not int or failure_count != 0:
        raise RuntimeError("AUTHORITY_BUNDLE_GCIS_FAILURES_PRESENT")
    if bundle.get("gcis_success_count") != bundle.get("gcis_seller_count"):
        raise RuntimeError("AUTHORITY_BUNDLE_GCIS_ACCOUNTING_MISMATCH")
    if not str(bundle.get("source_data_date", "")).strip():
        raise RuntimeError("AUTHORITY_BUNDLE_SOURCE_DATE_REQUIRED")
    return _self_hash(bundle, "authority_bundle_sha256", "AUTHORITY_BUNDLE")


def _fixture_source(head: str) -> dict[str, object]:
    payload: dict[str, object] = {
        "exact_head": head, "coverage": "nationwide", "validation_subset": False,
        "responsible_person_payload_emitted": False, "mobile_per_invoice_network_lookup": False,
        "source_data_date": "2026-09-03", "license_name": "ODGL-1.0", "license_url": "https://data.gov.tw/license",
        "attribution": "FIA", "official_dataset_identifier": "data.gov.tw/dataset/9400",
        "source_dataset": "MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY", "archive_url": "https://eip.fia.gov.tw/data/BGMOPEN1.zip",
        "source_last_modified": "Thu, 03 Sep 2026 21:13:24 GMT", "csv_member": "BGMOPEN1.csv",
        "source_archive_sha256": "a"*64, "source_csv_sha256": "b"*64, "source_archive_bytes": 10,
        "source_csv_bytes": 20, "source_row_count": 30, "acquisition_run_id": 41, "evidence_artifact_id": 123,
        "evidence_artifact_sha256": "c"*64,
    }
    payload["source_authority_sha256"] = hashlib.sha256(_canonical_bytes(payload)).hexdigest()
    return payload


def _fixture_closure(head: str, source: dict[str, object]) -> dict[str, object]:
    return {
        "exact_head": head, "final_mobile_registry": False,
        "gate": "P4.20.3-D-full-residual-acquisition-closure", "globally_sorted_combined_evidence_sha256": "d"*64,
        "mobile_per_invoice_network_lookup": False, "official_type_mapping_applied": False,
        "residual_payload_sha256": "e"*64, "responsible_person_payload_emitted": False,
        "schema_version": 3, "seller_count": 15757, "seller_set_sha256": "f"*64, "shard_count": 8,
        "source_archive_sha256": source["source_archive_sha256"], "source_authority_sha256": source["source_authority_sha256"],
        "source_last_modified": source["source_last_modified"], "source_row_count": source["source_row_count"],
        "total_failure_count": 0, "total_success_count": 15757, "validation_subset": False,
    }


def self_test() -> None:
    head = "1"*40
    source = _fixture_source(head)
    closure = _fixture_closure(head, source)
    bundle = build_authority_bundle(exact_head=head, source=source, closure=closure, gcis_workflow_run_id=15, gcis_artifact_id=9926389348, gcis_artifact_sha256="9"*64)
    assert validate_authority_bundle(bundle, head) == bundle["authority_bundle_sha256"]
    old_bundle = dict(bundle); old_bundle["exact_head"] = "2"*40; old_bundle["authority_bundle_sha256"] = hashlib.sha256(_canonical_bytes({k:v for k,v in old_bundle.items() if k != "authority_bundle_sha256"})).hexdigest()
    try:
        validate_authority_bundle(old_bundle, head); raise AssertionError("EXPECTED_BUNDLE_OLD_HEAD_HOLD")
    except RuntimeError as exc: assert str(exc) == "AUTHORITY_BUNDLE_EXACT_HEAD_MISMATCH"
    tampered = dict(bundle); tampered["gcis_artifact_id"] += 1
    try:
        validate_authority_bundle(tampered, head); raise AssertionError("EXPECTED_BUNDLE_TAMPER_HOLD")
    except RuntimeError as exc: assert str(exc) == "AUTHORITY_BUNDLE_SHA_MISMATCH"
    missing_bundle = dict(bundle); missing_bundle.pop("gcis_artifact_sha256")
    try:
        validate_authority_bundle(missing_bundle, head); raise AssertionError("EXPECTED_BUNDLE_MISSING_HOLD")
    except RuntimeError as exc: assert str(exc) == "AUTHORITY_BUNDLE_FIELD_MISSING:gcis_artifact_sha256"
    unknown_bundle = dict(bundle); unknown_bundle["unexpected"] = 1
    try:
        validate_authority_bundle(unknown_bundle, head); raise AssertionError("EXPECTED_BUNDLE_UNKNOWN_HOLD")
    except RuntimeError as exc: assert str(exc) == "AUTHORITY_BUNDLE_FIELD_UNKNOWN:unexpected"
    old = dict(closure); old["exact_head"] = "2"*40
    try:
        build_authority_bundle(exact_head=head, source=source, closure=old, gcis_workflow_run_id=15, gcis_artifact_id=1, gcis_artifact_sha256="9"*64); raise AssertionError("EXPECTED_OLD_HEAD_HOLD")
    except RuntimeError as exc: assert str(exc) == "GCIS_CLOSURE_EXACT_HEAD_MISMATCH"
    bad = dict(closure); bad["total_success_count"] -= 1
    try:
        build_authority_bundle(exact_head=head, source=source, closure=bad, gcis_workflow_run_id=15, gcis_artifact_id=1, gcis_artifact_sha256="9"*64); raise AssertionError("EXPECTED_SILENT_DROP_HOLD")
    except RuntimeError as exc: assert str(exc) == "GCIS_CLOSURE_SILENT_DROP_DETECTED"
    missing = dict(source); missing.pop("source_csv_sha256"); missing["source_authority_sha256"] = hashlib.sha256(_canonical_bytes({k:v for k,v in missing.items() if k != "source_authority_sha256"})).hexdigest()
    try:
        build_authority_bundle(exact_head=head, source=missing, closure=closure, gcis_workflow_run_id=15, gcis_artifact_id=1, gcis_artifact_sha256="9"*64); raise AssertionError("EXPECTED_REPLAY_FIELD_HOLD")
    except RuntimeError as exc: assert str(exc) == "SOURCE_AUTHORITY_SHA_FIELD_INVALID:source_csv_sha256"
    print("P4_20_3_DISTRIBUTION_AUTHORITY_BUNDLE_SELFTEST=PASS")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--self-test", action="store_true")
    p.add_argument("--exact-head")
    p.add_argument("--source-authority", type=Path)
    p.add_argument("--gcis-closure", type=Path)
    p.add_argument("--gcis-workflow-run-id", type=int)
    p.add_argument("--gcis-artifact-id", type=int)
    p.add_argument("--gcis-artifact-sha256")
    p.add_argument("--output", type=Path)
    a = p.parse_args()
    if a.self_test:
        self_test(); return 0
    required = (a.exact_head, a.source_authority, a.gcis_closure, a.gcis_workflow_run_id, a.gcis_artifact_id, a.gcis_artifact_sha256, a.output)
    if any(v is None for v in required):
        p.error("production mode requires all authority arguments")
    bundle = build_authority_bundle(exact_head=a.exact_head, source=_load(a.source_authority, "SOURCE_AUTHORITY"), closure=_load(a.gcis_closure, "GCIS_CLOSURE"), gcis_workflow_run_id=a.gcis_workflow_run_id, gcis_artifact_id=a.gcis_artifact_id, gcis_artifact_sha256=a.gcis_artifact_sha256)
    validate_authority_bundle(bundle, a.exact_head)
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_bytes(_canonical_bytes(bundle))
    print(f"P4_20_3_AUTHORITY_BUNDLE_SHA256={bundle['authority_bundle_sha256']}")
    print("P4_20_3_AUTHORITY_BUNDLE=PASS")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
