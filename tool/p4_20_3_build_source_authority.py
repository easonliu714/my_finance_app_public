#!/usr/bin/env python3
"""Build machine-readable source provenance authority for P4.20.3.

This Gate-E tool binds the exact nationwide FIA source artifact to official
catalog/license metadata before a production registry pack may be emitted.
It deliberately does not build a validation subset and does not ingest or emit
responsible-person data.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path

SCHEMA_VERSION = 1
DATASET_IDENTIFIER = "data.gov.tw/dataset/9400"
DATASET_NAME = "全國營業(稅籍)登記資料集"
DATASET_PAGE_URL = "https://data.gov.tw/dataset/9400"
ARCHIVE_URL = "https://eip.fia.gov.tw/data/BGMOPEN1.zip"
PROVIDER = "財政部財政資訊中心"
UPDATE_CADENCE = "daily"
LICENSE_NAME = "政府資料開放授權條款-第1版"
LICENSE_URL = "https://data.gov.tw/license"
SOURCE_DATASET = "MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY"
MAX_SOURCE_ARCHIVE_BYTES = 512 * 1024 * 1024
GIT_SHA_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def _canonical_bytes(value: object) -> bytes:
    return (
        json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n"
    ).encode("utf-8")


def _parse_http_last_modified(value: str) -> datetime:
    raw = value.strip()
    if not raw:
        raise ValueError("SOURCE_LAST_MODIFIED_REQUIRED")
    try:
        parsed = parsedate_to_datetime(raw)
    except (TypeError, ValueError) as exc:
        raise ValueError("SOURCE_LAST_MODIFIED_INVALID") from exc
    if parsed is None:
        raise ValueError("SOURCE_LAST_MODIFIED_INVALID")
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _validate_source_archive_bytes(value: object, *, error_code: str) -> int:
    try:
        archive_bytes = int(value)
    except (TypeError, ValueError, OverflowError) as exc:
        raise ValueError(error_code) from exc
    if archive_bytes <= 0 or archive_bytes > MAX_SOURCE_ARCHIVE_BYTES:
        raise ValueError(error_code)
    return archive_bytes


def build_authority(
    *,
    exact_head: str,
    source_last_modified: str,
    source_archive_sha256: str,
    source_archive_bytes: int,
    source_row_count: int,
) -> dict[str, object]:
    head = exact_head.strip().lower()
    archive_sha = source_archive_sha256.strip().lower()
    if not GIT_SHA_RE.fullmatch(head):
        raise ValueError("EXACT_HEAD_GIT_SHA_REQUIRED")
    if not SHA256_RE.fullmatch(archive_sha):
        raise ValueError("SOURCE_ARCHIVE_SHA256_INVALID")
    archive_bytes = _validate_source_archive_bytes(
        source_archive_bytes,
        error_code="SOURCE_ARCHIVE_BYTES_OUT_OF_BOUND",
    )
    if source_row_count <= 0:
        raise ValueError("SOURCE_ROW_COUNT_INVALID")

    modified = _parse_http_last_modified(source_last_modified)
    source_data_date = modified.date().isoformat()
    attribution = f"{PROVIDER} {modified.year} {DATASET_NAME}"

    payload: dict[str, object] = {
        "schema_version": SCHEMA_VERSION,
        "exact_head": head,
        "coverage": "nationwide",
        "source_dataset": SOURCE_DATASET,
        "official_dataset_identifier": DATASET_IDENTIFIER,
        "dataset_name": DATASET_NAME,
        "dataset_page_url": DATASET_PAGE_URL,
        "archive_url": ARCHIVE_URL,
        "provider": PROVIDER,
        "update_cadence": UPDATE_CADENCE,
        "source_last_modified": modified.strftime("%a, %d %b %Y %H:%M:%S GMT"),
        "source_data_date": source_data_date,
        "source_archive_sha256": archive_sha,
        "source_archive_bytes": archive_bytes,
        "source_row_count": source_row_count,
        "license_name": LICENSE_NAME,
        "license_url": LICENSE_URL,
        "attribution": attribution,
        "validation_subset": False,
        "responsible_person_payload_emitted": False,
        "mobile_per_invoice_network_lookup": False,
    }
    authority_sha = hashlib.sha256(_canonical_bytes(payload)).hexdigest()
    return {**payload, "source_authority_sha256": authority_sha}


def validate_authority(authority: dict[str, object]) -> None:
    expected_constants = {
        "schema_version": SCHEMA_VERSION,
        "coverage": "nationwide",
        "source_dataset": SOURCE_DATASET,
        "official_dataset_identifier": DATASET_IDENTIFIER,
        "dataset_name": DATASET_NAME,
        "dataset_page_url": DATASET_PAGE_URL,
        "archive_url": ARCHIVE_URL,
        "provider": PROVIDER,
        "update_cadence": UPDATE_CADENCE,
        "license_name": LICENSE_NAME,
        "license_url": LICENSE_URL,
        "validation_subset": False,
        "responsible_person_payload_emitted": False,
        "mobile_per_invoice_network_lookup": False,
    }
    for key, expected in expected_constants.items():
        if authority.get(key) != expected:
            raise ValueError(f"SOURCE_AUTHORITY_CONSTANT_DRIFT:{key}")

    if not GIT_SHA_RE.fullmatch(str(authority.get("exact_head", ""))):
        raise ValueError("SOURCE_AUTHORITY_EXACT_HEAD_INVALID")
    if not SHA256_RE.fullmatch(str(authority.get("source_archive_sha256", ""))):
        raise ValueError("SOURCE_AUTHORITY_ARCHIVE_SHA_INVALID")
    _validate_source_archive_bytes(
        authority.get("source_archive_bytes", 0),
        error_code="SOURCE_AUTHORITY_ARCHIVE_BYTES_INVALID",
    )
    if int(authority.get("source_row_count", 0)) <= 0:
        raise ValueError("SOURCE_AUTHORITY_ROW_COUNT_INVALID")

    modified = _parse_http_last_modified(str(authority.get("source_last_modified", "")))
    if authority.get("source_data_date") != modified.date().isoformat():
        raise ValueError("SOURCE_AUTHORITY_DATE_MISMATCH")
    expected_attribution = f"{PROVIDER} {modified.year} {DATASET_NAME}"
    if authority.get("attribution") != expected_attribution:
        raise ValueError("SOURCE_AUTHORITY_ATTRIBUTION_INVALID")

    actual_sha = str(authority.get("source_authority_sha256", ""))
    payload = dict(authority)
    payload.pop("source_authority_sha256", None)
    expected_sha = hashlib.sha256(_canonical_bytes(payload)).hexdigest()
    if actual_sha != expected_sha:
        raise ValueError("SOURCE_AUTHORITY_SHA_MISMATCH")


def _self_test() -> None:
    authority = build_authority(
        exact_head="a" * 40,
        source_last_modified="Tue, 01 Sep 2026 21:11:34 GMT",
        source_archive_sha256="b" * 64,
        source_archive_bytes=66299794,
        source_row_count=1712892,
    )
    validate_authority(authority)
    assert authority["source_data_date"] == "2026-09-01"
    assert authority["coverage"] == "nationwide"
    assert authority["validation_subset"] is False

    tampered = dict(authority)
    tampered["source_row_count"] = 1
    try:
        validate_authority(tampered)
    except ValueError as exc:
        assert str(exc) == "SOURCE_AUTHORITY_SHA_MISMATCH"
    else:
        raise AssertionError("tampered authority unexpectedly passed")

    oversized_rehashed = dict(authority)
    oversized_rehashed["source_archive_bytes"] = MAX_SOURCE_ARCHIVE_BYTES + 1
    oversized_payload = dict(oversized_rehashed)
    oversized_payload.pop("source_authority_sha256", None)
    oversized_rehashed["source_authority_sha256"] = hashlib.sha256(
        _canonical_bytes(oversized_payload)
    ).hexdigest()
    try:
        validate_authority(oversized_rehashed)
    except ValueError as exc:
        assert str(exc) == "SOURCE_AUTHORITY_ARCHIVE_BYTES_INVALID"
    else:
        raise AssertionError("rehashed oversized authority unexpectedly passed")

    try:
        build_authority(
            exact_head="a" * 64,
            source_last_modified="Tue, 01 Sep 2026 21:11:34 GMT",
            source_archive_sha256="b" * 64,
            source_archive_bytes=66299794,
            source_row_count=1712892,
        )
    except ValueError as exc:
        assert str(exc) == "EXACT_HEAD_GIT_SHA_REQUIRED"
    else:
        raise AssertionError("64-hex non-Git exact head unexpectedly passed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--exact-head")
    parser.add_argument("--source-last-modified")
    parser.add_argument("--source-archive-sha256")
    parser.add_argument("--source-archive-bytes", type=int)
    parser.add_argument("--source-row-count", type=int)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        _self_test()
        print("P4_20_3_SOURCE_AUTHORITY_SELF_TEST=PASS")
        return 0

    required = (
        args.exact_head,
        args.source_last_modified,
        args.source_archive_sha256,
        args.source_archive_bytes,
        args.source_row_count,
        args.output,
    )
    if any(value is None for value in required):
        parser.error("production mode requires all source authority arguments")

    authority = build_authority(
        exact_head=args.exact_head,
        source_last_modified=args.source_last_modified,
        source_archive_sha256=args.source_archive_sha256,
        source_archive_bytes=args.source_archive_bytes,
        source_row_count=args.source_row_count,
    )
    validate_authority(authority)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(_canonical_bytes(authority))
    print(f"SOURCE_AUTHORITY_SHA256={authority['source_authority_sha256']}")
    print("P4_20_3_SOURCE_AUTHORITY=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
