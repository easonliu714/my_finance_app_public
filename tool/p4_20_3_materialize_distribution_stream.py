#!/usr/bin/env python3
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import re
from datetime import timezone
from email.utils import parsedate_to_datetime
from pathlib import Path

SOURCE_AUTHORITY = "MOF_FIA_ACTIVE_TAX_REGISTRY"
SOURCE_DATASET = "MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY"
COVERAGE = "taiwan_nationwide"
FORMAT = "gzip_ndjson_v1"
OFFICIAL_FIELD_COUNT = 16
DOWNLOAD_URL = (
    "https://github.com/easonliu714/my_finance_app_public/releases/download/"
    "p4.20.3-registry/nationwide_registry.ndjson.gz"
)


def _json_line(value: dict[str, object]) -> bytes:
    return (json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")


def _entity_line(source: dict[str, object]) -> bytes:
    seller = str(source.get("seller_identifier", "")).strip()
    legal_name = str(source.get("legal_name", "")).strip()
    details = source.get("official_fields")
    if not isinstance(details, list) or len(details) != OFFICIAL_FIELD_COUNT:
        raise ValueError("OFFICIAL_DETAIL_16_FIELD_CONTRACT_MISMATCH")
    values = [str(item).strip() if item is not None else "" for item in details]
    if re.sub(r"[^0-9]", "", values[1]) != seller:
        raise ValueError("OFFICIAL_DETAIL_SELLER_MISMATCH")
    if values[3] != legal_name:
        raise ValueError("OFFICIAL_DETAIL_LEGAL_NAME_MISMATCH")
    return _json_line({
        "record_type": "entity",
        "seller_identifier": seller,
        "entity_type": str(source.get("entity_type", "")).strip(),
        "legal_name": legal_name,
        "registration_status": str(source.get("registration_status", "")).strip(),
        "parent_seller_identifier": str(source.get("parent_seller_identifier", "")).strip(),
        "source_dataset": str(source.get("source_dataset", "")).strip(),
        "official_fields": values,
    })


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as src:
        for chunk in iter(lambda: src.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _last_modified(root: Path) -> str:
    for line in (root / "source_headers.txt").read_text(encoding="utf-8", errors="replace").splitlines():
        if line.lower().startswith("last-modified:"):
            return line.split(":", 1)[1].strip()
    raise ValueError("FIA_LAST_MODIFIED_REQUIRED")


def materialize(root: Path, exact_head: str) -> dict[str, object]:
    stage = json.loads((root / "staging" / "staging_summary.json").read_text(encoding="utf-8"))
    canonical = json.loads((root / "canonical_summary.json").read_text(encoding="utf-8"))
    raw = root / "nationwide_registry.ndjson"
    gz = root / "nationwide_registry.ndjson.gz"
    rows = int(stage["source_row_count"])
    invalid = int(stage["source_invalid_row_count"])
    valid = int(stage["source_valid_identity_count"])
    emitted = int(canonical["canonical_entity_count"])
    if emitted != valid or valid != rows - invalid:
        raise ValueError("SOURCE_VALID_IDENTITY_ACCOUNTING_MISMATCH")

    content_hash = hashlib.sha256()
    entity_bytes = 0
    entity_count = 0
    with raw.open("r", encoding="utf-8") as src:
        for line in src:
            if not line.strip():
                continue
            record = _entity_line(json.loads(line))
            content_hash.update(record)
            entity_bytes += len(record)
            entity_count += 1
    if entity_count != emitted:
        raise ValueError("INSTALLABLE_STREAM_ENTITY_COUNT_MISMATCH")

    registry_content_sha256 = content_hash.hexdigest()
    last_modified = _last_modified(root)
    dt = parsedate_to_datetime(last_modified)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    source_data_date = dt.astimezone(timezone.utc).date().isoformat()
    source_archive_sha256 = str(stage["source_archive_sha256"]).lower()
    if not re.fullmatch(r"[0-9a-f]{64}", source_archive_sha256):
        raise ValueError("FIA_SOURCE_ARCHIVE_SHA256_INVALID")
    registry_version = f"p4.20.3-fia-{source_data_date}-{source_archive_sha256[:12]}"
    header = _json_line({
        "record_type": "header",
        "registry_version": registry_version,
        "source_authority": SOURCE_AUTHORITY,
        "source_dataset": SOURCE_DATASET,
        "source_data_date": source_data_date,
        "coverage": COVERAGE,
        "entity_count": emitted,
        "registry_content_sha256": registry_content_sha256,
    })
    uncompressed_size = len(header) + entity_bytes

    with gz.open("wb") as sink:
        with gzip.GzipFile(filename="", mode="wb", fileobj=sink, compresslevel=9, mtime=0) as dst:
            dst.write(header)
            with raw.open("r", encoding="utf-8") as src:
                for line in src:
                    if line.strip():
                        dst.write(_entity_line(json.loads(line)))

    compressed_size = gz.stat().st_size
    if compressed_size > 256 * 1024 * 1024:
        raise ValueError("REGISTRY_DISTRIBUTION_COMPRESSED_SIZE_INVALID")
    if uncompressed_size > 1024 * 1024 * 1024:
        raise ValueError("REGISTRY_DISTRIBUTION_UNCOMPRESSED_SIZE_INVALID")
    download_sha256 = _sha256_file(gz)
    manifest: dict[str, object] = {
        "schema_version": 1,
        "gate": "P4.20.3-E-fia-invoice-lookup-mobile-registry",
        "exact_head": exact_head,
        "registry_version": registry_version,
        "source_authority": SOURCE_AUTHORITY,
        "source_dataset": SOURCE_DATASET,
        "source_data_date": source_data_date,
        "source_last_modified": last_modified,
        "official_dataset_identifier": "data.gov.tw/dataset/9400",
        "source_archive_sha256": source_archive_sha256,
        "source_row_count": rows,
        "source_invalid_row_count": invalid,
        "source_valid_identity_count": valid,
        "canonical_entity_count": emitted,
        "entity_count": emitted,
        "official_detail_16_field_count": emitted,
        "company_count": canonical["company_count"],
        "business_count": canonical["business_count"],
        "branch_count": canonical["branch_count"],
        "unknown_count": canonical["unknown_count"],
        "unresolved_parent_reference_count": canonical["unresolved_parent_reference_count"],
        "parent_reference_points_to_branch_count": canonical["parent_reference_points_to_branch_count"],
        "parent_reference_is_release_blocker": False,
        "legal_subtype_is_release_blocker": False,
        "gcis_enrichment_required_for_release": False,
        "coverage": COVERAGE,
        "coverage_description": "taiwan_nationwide_valid_seller_identity",
        "source_valid_identity_coverage_complete": True,
        "production_registry_usable": True,
        "final_mobile_registry": True,
        "optional_local_dataset": True,
        "validation_subset": False,
        "mobile_per_invoice_network_lookup": False,
        "responsible_person_payload_emitted": False,
        "user_owned_mapping_or_history_mutated": False,
        "format": FORMAT,
        "artifact_encoding": FORMAT,
        "download_url": DOWNLOAD_URL,
        "download_sha256": download_sha256,
        "artifact_sha256": download_sha256,
        "compressed_size_bytes": compressed_size,
        "artifact_bytes": compressed_size,
        "registry_content_sha256": registry_content_sha256,
        "canonical_entities_sha256": registry_content_sha256,
        "canonical_entities_bytes": entity_bytes,
        "uncompressed_size_bytes": uncompressed_size,
        "license_name": "政府資料開放授權條款",
        "license_url": "https://data.gov.tw/license",
        "attribution": "財政部財政資訊中心",
    }
    payload = _json_line(dict(sorted(manifest.items())))
    manifest["manifest_sha256"] = hashlib.sha256(payload).hexdigest()
    (root / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("--exact-head", required=True)
    args = parser.parse_args()
    manifest = materialize(args.root, args.exact_head)
    print("P4_20_3_REAL_FIA_INSTALLABLE_STREAM=PASS")
    print(f"P4_20_3_REAL_FIA_MOBILE_ENTITY_COUNT={manifest['entity_count']}")
    print(f"P4_20_3_REAL_FIA_OFFICIAL_DETAIL_16_FIELD_COUNT={manifest['official_detail_16_field_count']}")
    print(f"P4_20_3_REAL_FIA_MOBILE_COMPRESSED_BYTES={manifest['compressed_size_bytes']}")
    print(f"P4_20_3_REAL_FIA_MOBILE_UNCOMPRESSED_BYTES={manifest['uncompressed_size_bytes']}")
    print(f"P4_20_3_REAL_FIA_MOBILE_ARTIFACT_SHA256={manifest['download_sha256']}")
    print(f"P4_20_3_REAL_FIA_REGISTRY_CONTENT_SHA256={manifest['registry_content_sha256']}")
    print("P4_20_3_REAL_FIA_MOBILE_FINAL=true")


if __name__ == "__main__":
    main()
