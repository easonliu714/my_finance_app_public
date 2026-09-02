#!/usr/bin/env python3
"""Inspect the official FIA nationwide active tax-registration archive.

This is an acquisition/evidence tool, not the final canonical registry builder.
It streams the CSV member directly from the ZIP, validates source shape, records
quality counters and selected real seller-ID probes, and never loads all rows
into memory.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path

REQUIRED_COLUMNS = (
    "統一編號",
    "總機構統一編號",
    "營業人名稱",
    "組織別名稱",
    "使用統一發票",
)
SELLER_RE = re.compile(r"^\d{8}$")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inspect_archive(
    archive: Path,
    *,
    probes: set[str],
    min_rows: int,
) -> dict[str, object]:
    if not archive.is_file():
        raise RuntimeError("FIA_ARCHIVE_MISSING")

    archive_bytes = archive.stat().st_size
    if archive_bytes <= 0:
        raise RuntimeError("FIA_ARCHIVE_EMPTY")
    if archive_bytes > 512 * 1024 * 1024:
        raise RuntimeError("FIA_ARCHIVE_EXCEEDS_512MIB_BOUND")

    with zipfile.ZipFile(archive) as zf:
        bad_member = zf.testzip()
        if bad_member is not None:
            raise RuntimeError(f"FIA_ZIP_INTEGRITY_FAIL:{bad_member}")
        csv_members = [
            info
            for info in zf.infolist()
            if not info.is_dir() and info.filename.lower().endswith(".csv")
        ]
        if len(csv_members) != 1:
            raise RuntimeError(
                f"FIA_EXPECTED_EXACTLY_ONE_CSV_MEMBER:{len(csv_members)}"
            )
        member = csv_members[0]
        if member.file_size <= 0:
            raise RuntimeError("FIA_CSV_MEMBER_EMPTY")
        if member.file_size > 2 * 1024 * 1024 * 1024:
            raise RuntimeError("FIA_CSV_MEMBER_EXCEEDS_2GIB_BOUND")

        row_count = 0
        invalid_seller_count = 0
        empty_name_count = 0
        invalid_parent_count = 0
        parent_self_reference_count = 0
        found_probes: dict[str, dict[str, str]] = {}

        with zf.open(member, "r") as raw:
            import io

            text = io.TextIOWrapper(raw, encoding="utf-8-sig", newline="")
            reader = csv.DictReader(text)
            header = tuple((reader.fieldnames or ()))
            missing = [column for column in REQUIRED_COLUMNS if column not in header]
            if missing:
                raise RuntimeError(
                    "FIA_REQUIRED_COLUMNS_MISSING:" + ",".join(missing)
                )

            for row in reader:
                row_count += 1
                seller = re.sub(r"\D", "", row.get("統一編號") or "")
                parent = re.sub(r"\D", "", row.get("總機構統一編號") or "")
                name = (row.get("營業人名稱") or "").strip()
                if not SELLER_RE.fullmatch(seller):
                    invalid_seller_count += 1
                if not name:
                    empty_name_count += 1
                if parent and not SELLER_RE.fullmatch(parent):
                    invalid_parent_count += 1
                if parent and parent == seller:
                    parent_self_reference_count += 1
                if seller in probes and seller not in found_probes:
                    found_probes[seller] = {
                        "seller_identifier": seller,
                        "legal_name": name,
                        "parent_seller_identifier": parent,
                        "organization_type": (row.get("組織別名稱") or "").strip(),
                        "uses_uniform_invoice": (row.get("使用統一發票") or "").strip(),
                    }

    if row_count < min_rows:
        raise RuntimeError(f"FIA_ROW_COUNT_BELOW_NATIONWIDE_FLOOR:{row_count}")

    return {
        "schema_version": 1,
        "dataset": "全國營業(稅籍)登記資料集",
        "provider": "財政部財政資訊中心",
        "catalog_url": "https://data.gov.tw/dataset/9400",
        "acquisition_url": "https://eip.fia.gov.tw/data/BGMOPEN1.zip",
        "acquired_at_utc": datetime.now(timezone.utc).isoformat(),
        "archive_sha256": sha256_file(archive),
        "archive_bytes": archive_bytes,
        "csv_member": member.filename,
        "csv_uncompressed_bytes": member.file_size,
        "row_count": row_count,
        "required_columns": list(REQUIRED_COLUMNS),
        "quality": {
            "invalid_seller_count": invalid_seller_count,
            "empty_name_count": empty_name_count,
            "invalid_parent_count": invalid_parent_count,
            "parent_self_reference_count": parent_self_reference_count,
        },
        "probe_results": {
            probe: found_probes.get(probe) for probe in sorted(probes)
        },
        "coverage_claim": "nationwide_active_tax_registration_source",
        "license": "政府資料開放授權條款-第1版",
        "license_url": "https://data.gov.tw/license",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--probe", action="append", default=[])
    parser.add_argument("--min-rows", type=int, default=1_000_000)
    args = parser.parse_args()

    probes = {re.sub(r"\D", "", value) for value in args.probe}
    if any(not SELLER_RE.fullmatch(value) for value in probes):
        raise SystemExit("FIA_PROBE_IDENTIFIER_INVALID")

    try:
        evidence = inspect_archive(
            args.archive,
            probes=probes,
            min_rows=args.min_rows,
        )
    except Exception as exc:  # fail closed with one deterministic marker
        print(f"P4_20_3_FIA_INSPECTION=HOLD:{exc}", file=sys.stderr)
        return 2

    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    args.evidence.write_text(
        json.dumps(evidence, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print("P4_20_3_FIA_INSPECTION=PASS")
    print(f"FIA_ROWS={evidence['row_count']}")
    print(f"FIA_ARCHIVE_SHA256={evidence['archive_sha256']}")
    for seller, result in evidence["probe_results"].items():
        status = "HIT" if result else "MISS"
        print(f"FIA_PROBE_{seller}={status}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
