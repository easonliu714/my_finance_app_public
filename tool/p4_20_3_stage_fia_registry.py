#!/usr/bin/env python3
"""Bounded deterministic staging pass for the P4.20.3 FIA nationwide registry.

This tool is deliberately *not* the final nationwide mobile registry builder.
It proves that the full BGMOPEN1 CSV can be converted with bounded memory into
canonical ready entities plus a deterministic legal-enrichment queue while
preserving fail-closed rows separately by count.

Only public business-registration fields required by the mobile registry are
projected. Responsible-person / branch-manager data is never emitted.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import heapq
import io
import json
import re
import shutil
import sys
import tempfile
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator

REQUIRED_COLUMNS = (
    "統一編號",
    "總機構統一編號",
    "營業人名稱",
    "組織別名稱",
    "使用統一發票",
)
SELLER_RE = re.compile(r"^\d{8}$")
SOURCE_DATASET = "MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY"
COMPANY_FORMS = frozenset({"有限公司", "股份有限公司", "無限公司", "兩合公司"})
BUSINESS_FORMS = frozenset({"獨資", "合夥"})


def _digits(value: str) -> str:
    return re.sub(r"\D", "", value or "")


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _canonical_json(record: dict[str, str]) -> str:
    return json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n"


@dataclass(frozen=True)
class StageRecord:
    status: str
    key: str = ""
    line: str = ""
    reason: str = ""


def stage_row(row: dict[str, str]) -> StageRecord:
    seller = _digits(row.get("統一編號") or "")
    parent = _digits(row.get("總機構統一編號") or "")
    legal_name = (row.get("營業人名稱") or "").strip()
    organization = (row.get("組織別名稱") or "").strip()
    uniform_invoice = (row.get("使用統一發票") or "").strip()

    if not SELLER_RE.fullmatch(seller):
        return StageRecord("hold", reason="seller_identifier_invalid")
    if not legal_name:
        return StageRecord("hold", reason="legal_name_required")
    if parent and not SELLER_RE.fullmatch(parent):
        return StageRecord("hold", reason="parent_identifier_invalid")
    if parent == seller:
        return StageRecord("hold", reason="parent_self_reference")

    if parent:
        entity_type = "branch"
    elif organization in COMPANY_FORMS:
        entity_type = "company"
    elif organization in BUSINESS_FORMS:
        entity_type = "business"
    else:
        queue_record = {
            "seller_identifier": seller,
            "legal_name": legal_name,
            "organization_type": organization,
            "uses_uniform_invoice": uniform_invoice,
            "source_dataset": SOURCE_DATASET,
        }
        return StageRecord(
            "enrichment_required",
            key=seller,
            line=_canonical_json(queue_record),
            reason="parentless_fia_row_requires_company_or_business_authority",
        )

    entity = {
        "record_type": "entity",
        "seller_identifier": seller,
        "entity_type": entity_type,
        "legal_name": legal_name,
        "registration_status": "active_tax_registration",
        "parent_seller_identifier": parent if entity_type == "branch" else "",
        "source_dataset": SOURCE_DATASET,
    }
    return StageRecord(
        "ready",
        key=f"{seller}|{entity_type}",
        line=_canonical_json(entity),
    )


class ExternalLineSorter:
    """Bounded row-count external sorter with deterministic k-way merge."""

    def __init__(self, directory: Path, *, prefix: str, max_rows: int) -> None:
        if max_rows <= 0:
            raise ValueError("STAGING_CHUNK_ROWS_MUST_BE_POSITIVE")
        self.directory = directory
        self.prefix = prefix
        self.max_rows = max_rows
        self.buffer: list[tuple[str, str]] = []
        self.chunk_paths: list[Path] = []
        self.peak_buffer_rows = 0
        self.total_added = 0

    def add(self, key: str, line: str) -> None:
        if not key or not line.endswith("\n"):
            raise ValueError("STAGING_SORT_RECORD_INVALID")
        self.buffer.append((key, line))
        self.total_added += 1
        self.peak_buffer_rows = max(self.peak_buffer_rows, len(self.buffer))
        if len(self.buffer) >= self.max_rows:
            self._flush()

    def _flush(self) -> None:
        if not self.buffer:
            return
        self.buffer.sort(key=lambda item: (item[0], item[1]))
        path = self.directory / f"{self.prefix}_{len(self.chunk_paths):06d}.chunk"
        with path.open("w", encoding="utf-8", newline="") as out:
            for key, line in self.buffer:
                out.write(key)
                out.write("\t")
                out.write(line)
        self.chunk_paths.append(path)
        self.buffer.clear()

    @staticmethod
    def _iter_chunk(path: Path) -> Iterator[tuple[str, str]]:
        with path.open("r", encoding="utf-8", newline="") as stream:
            for raw in stream:
                key, separator, line = raw.partition("\t")
                if not separator or not key or not line.endswith("\n"):
                    raise RuntimeError("STAGING_CHUNK_RECORD_INVALID")
                yield key, line

    def merge_to(
        self,
        output: Path,
        *,
        hash_payload: bool,
        duplicate_error: str,
    ) -> tuple[int, str, int]:
        self._flush()
        output.parent.mkdir(parents=True, exist_ok=True)
        digest = hashlib.sha256()
        count = 0
        previous_key: str | None = None
        iterators = [self._iter_chunk(path) for path in self.chunk_paths]
        merged = heapq.merge(*iterators, key=lambda item: (item[0], item[1]))
        with output.open("w", encoding="utf-8", newline="") as out:
            for key, line in merged:
                if key == previous_key:
                    raise RuntimeError(duplicate_error)
                previous_key = key
                out.write(line)
                if hash_payload:
                    digest.update(line.encode("utf-8"))
                count += 1
        if count != self.total_added:
            raise RuntimeError("STAGING_EXTERNAL_SORT_COUNT_MISMATCH")
        return count, digest.hexdigest() if hash_payload else "", output.stat().st_size


def _single_csv_member(zf: zipfile.ZipFile) -> zipfile.ZipInfo:
    members = [
        info
        for info in zf.infolist()
        if not info.is_dir() and info.filename.lower().endswith(".csv")
    ]
    if len(members) != 1:
        raise RuntimeError(f"FIA_EXPECTED_EXACTLY_ONE_CSV_MEMBER:{len(members)}")
    return members[0]


def stage_archive(
    archive: Path,
    output_dir: Path,
    *,
    max_chunk_rows: int,
    min_rows: int,
) -> dict[str, object]:
    if not archive.is_file():
        raise RuntimeError("FIA_ARCHIVE_MISSING")
    if archive.stat().st_size <= 0:
        raise RuntimeError("FIA_ARCHIVE_EMPTY")
    if archive.stat().st_size > 512 * 1024 * 1024:
        raise RuntimeError("FIA_ARCHIVE_EXCEEDS_512MIB_BOUND")

    output_dir.mkdir(parents=True, exist_ok=True)
    work_dir = output_dir / ".chunks"
    if work_dir.exists():
        shutil.rmtree(work_dir)
    work_dir.mkdir(parents=True)

    ready_output = output_dir / "ready_entities.ndjson"
    enrichment_output = output_dir / "enrichment_required.ndjson"
    summary_output = output_dir / "staging_summary.json"
    for path in (ready_output, enrichment_output, summary_output):
        if path.exists():
            path.unlink()

    ready_sorter = ExternalLineSorter(
        work_dir, prefix="ready", max_rows=max_chunk_rows
    )
    enrichment_sorter = ExternalLineSorter(
        work_dir, prefix="enrichment", max_rows=max_chunk_rows
    )
    row_count = 0
    hold_count = 0
    hold_reasons: dict[str, int] = {}

    try:
        with zipfile.ZipFile(archive) as zf:
            bad_member = zf.testzip()
            if bad_member is not None:
                raise RuntimeError(f"FIA_ZIP_INTEGRITY_FAIL:{bad_member}")
            member = _single_csv_member(zf)
            if member.file_size <= 0:
                raise RuntimeError("FIA_CSV_MEMBER_EMPTY")
            if member.file_size > 2 * 1024 * 1024 * 1024:
                raise RuntimeError("FIA_CSV_MEMBER_EXCEEDS_2GIB_BOUND")

            with zf.open(member, "r") as raw:
                text = io.TextIOWrapper(raw, encoding="utf-8-sig", newline="")
                reader = csv.DictReader(text)
                header = tuple(reader.fieldnames or ())
                missing = [field for field in REQUIRED_COLUMNS if field not in header]
                if missing:
                    raise RuntimeError(
                        "FIA_REQUIRED_COLUMNS_MISSING:" + ",".join(missing)
                    )
                for row in reader:
                    row_count += 1
                    staged = stage_row(row)
                    if staged.status == "ready":
                        ready_sorter.add(staged.key, staged.line)
                    elif staged.status == "enrichment_required":
                        enrichment_sorter.add(staged.key, staged.line)
                    elif staged.status == "hold":
                        hold_count += 1
                        hold_reasons[staged.reason] = hold_reasons.get(staged.reason, 0) + 1
                    else:
                        raise RuntimeError("STAGING_STATUS_UNSUPPORTED")

        if row_count < min_rows:
            raise RuntimeError(f"FIA_ROW_COUNT_BELOW_NATIONWIDE_FLOOR:{row_count}")

        ready_count, ready_sha, ready_bytes = ready_sorter.merge_to(
            ready_output,
            hash_payload=True,
            duplicate_error="STAGING_DUPLICATE_READY_ENTITY_KEY",
        )
        enrichment_count, _, enrichment_bytes = enrichment_sorter.merge_to(
            enrichment_output,
            hash_payload=False,
            duplicate_error="STAGING_DUPLICATE_ENRICHMENT_SELLER_IDENTIFIER",
        )
        if ready_count + enrichment_count + hold_count != row_count:
            raise RuntimeError("STAGING_ROW_PARTITION_MISMATCH")
        if ready_sorter.peak_buffer_rows > max_chunk_rows:
            raise RuntimeError("STAGING_READY_BUFFER_BOUND_EXCEEDED")
        if enrichment_sorter.peak_buffer_rows > max_chunk_rows:
            raise RuntimeError("STAGING_ENRICHMENT_BUFFER_BOUND_EXCEEDED")

        summary: dict[str, object] = {
            "schema_version": 1,
            "stage": "fia_privacy_reduced_bounded_staging",
            "final_mobile_registry": False,
            "source_dataset": SOURCE_DATASET,
            "source_archive_sha256": _sha256_file(archive),
            "source_row_count": row_count,
            "ready_entity_count": ready_count,
            "enrichment_required_count": enrichment_count,
            "hold_count": hold_count,
            "hold_reason_counts": dict(sorted(hold_reasons.items())),
            "ready_entity_payload_sha256": ready_sha,
            "ready_entity_bytes": ready_bytes,
            "enrichment_queue_bytes": enrichment_bytes,
            "external_sort_chunk_row_bound": max_chunk_rows,
            "ready_peak_buffer_rows": ready_sorter.peak_buffer_rows,
            "enrichment_peak_buffer_rows": enrichment_sorter.peak_buffer_rows,
            "coverage_claim": "staging_only_not_nationwide_mobile_pack",
            "responsible_person_payload_emitted": False,
        }
        summary_output.write_text(
            json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        return summary
    except Exception:
        for path in (ready_output, enrichment_output, summary_output):
            if path.exists():
                path.unlink()
        raise
    finally:
        if work_dir.exists():
            shutil.rmtree(work_dir)


def _self_test() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        archive = root / "fixture.zip"
        csv_text = io.StringIO(newline="")
        writer = csv.DictWriter(
            csv_text,
            fieldnames=(*REQUIRED_COLUMNS, "負責人姓名"),
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(
            [
                {
                    "統一編號": "22222222",
                    "總機構統一編號": "11111111",
                    "營業人名稱": "分支測試",
                    "組織別名稱": "其他",
                    "使用統一發票": "Y",
                    "負責人姓名": "MUST_NOT_LEAK",
                },
                {
                    "統一編號": "33333333",
                    "總機構統一編號": "",
                    "營業人名稱": "公司測試",
                    "組織別名稱": "有限公司",
                    "使用統一發票": "Y",
                    "負責人姓名": "MUST_NOT_LEAK",
                },
                {
                    "統一編號": "44444444",
                    "總機構統一編號": "",
                    "營業人名稱": "商業測試",
                    "組織別名稱": "獨資",
                    "使用統一發票": "N",
                    "負責人姓名": "MUST_NOT_LEAK",
                },
                {
                    "統一編號": "55555555",
                    "總機構統一編號": "",
                    "營業人名稱": "待增補測試",
                    "組織別名稱": "合作社",
                    "使用統一發票": "Y",
                    "負責人姓名": "MUST_NOT_LEAK",
                },
                {
                    "統一編號": "INVALID",
                    "總機構統一編號": "",
                    "營業人名稱": "錯誤測試",
                    "組織別名稱": "獨資",
                    "使用統一發票": "Y",
                    "負責人姓名": "MUST_NOT_LEAK",
                },
            ]
        )
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            zf.writestr("BGMOPEN1.csv", csv_text.getvalue().encode("utf-8-sig"))

        summary = stage_archive(
            archive,
            root / "out",
            max_chunk_rows=2,
            min_rows=1,
        )
        assert summary["source_row_count"] == 5
        assert summary["ready_entity_count"] == 3
        assert summary["enrichment_required_count"] == 1
        assert summary["hold_count"] == 1
        assert summary["ready_peak_buffer_rows"] <= 2
        assert summary["enrichment_peak_buffer_rows"] <= 2
        ready = (root / "out" / "ready_entities.ndjson").read_text(encoding="utf-8")
        queue = (root / "out" / "enrichment_required.ndjson").read_text(
            encoding="utf-8"
        )
        assert "MUST_NOT_LEAK" not in ready
        assert "MUST_NOT_LEAK" not in queue
        parsed = [json.loads(line) for line in ready.splitlines()]
        assert [item["seller_identifier"] for item in parsed] == [
            "22222222",
            "33333333",
            "44444444",
        ]
        assert [item["entity_type"] for item in parsed] == [
            "branch",
            "company",
            "business",
        ]
        assert json.loads(queue)["seller_identifier"] == "55555555"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path, nargs="?")
    parser.add_argument("output_dir", type=Path, nargs="?")
    parser.add_argument("--chunk-rows", type=int, default=50_000)
    parser.add_argument("--min-rows", type=int, default=1_000_000)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    try:
        if args.self_test:
            _self_test()
            print("P4_20_3_FIA_STAGING_SELFTEST=PASS")
            return 0
        if args.archive is None or args.output_dir is None:
            parser.error("archive and output_dir are required unless --self-test is used")
        summary = stage_archive(
            args.archive,
            args.output_dir,
            max_chunk_rows=args.chunk_rows,
            min_rows=args.min_rows,
        )
    except Exception as exc:
        print(f"P4_20_3_FIA_STAGING=HOLD:{exc}", file=sys.stderr)
        return 2

    print("P4_20_3_FIA_STAGING=PASS")
    print(f"STAGING_SOURCE_ROWS={summary['source_row_count']}")
    print(f"STAGING_READY_ENTITIES={summary['ready_entity_count']}")
    print(f"STAGING_ENRICHMENT_REQUIRED={summary['enrichment_required_count']}")
    print(f"STAGING_HOLD_ROWS={summary['hold_count']}")
    print(f"STAGING_READY_SHA256={summary['ready_entity_payload_sha256']}")
    print(f"STAGING_CHUNK_ROW_BOUND={summary['external_sort_chunk_row_bound']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
