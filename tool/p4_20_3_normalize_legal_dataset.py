#!/usr/bin/env python3
"""P4.20.3 Gate D controlled-build legal dataset normalizer.

Converts official MOEA/GCIS CSV exports into the privacy-reduced, externally
sorted NDJSON contract consumed by p4_20_3_reconcile_legal_enrichment.py.
Responsible-person / representative / manager fields are never serialized.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import heapq
import json
import tempfile
from pathlib import Path
from typing import Iterator

OUTPUT_KEYS = {
    "seller_identifier",
    "entity_type",
    "legal_name",
    "registration_status",
    "parent_seller_identifier",
    "source_dataset",
}
LICENSE = "政府資料開放授權條款-第1版"


def _clean(value: object) -> str:
    return str(value or "").strip()


def _seller(value: object) -> str:
    digits = "".join(ch for ch in _clean(value) if ch.isdigit())
    return digits if len(digits) == 8 else ""


def _line(record: dict[str, object]) -> bytes:
    return (json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")


def _normalize_row(
    raw: dict[str, str],
    *,
    entity_type: str,
    seller_col: str,
    name_col: str,
    status_col: str,
    parent_col: str,
    source_dataset: str,
) -> tuple[dict[str, object] | None, str]:
    seller = _seller(raw.get(seller_col))
    if not seller:
        return None, "invalid_seller_identifier"
    legal_name = _clean(raw.get(name_col))
    if not legal_name:
        return None, "empty_legal_name"
    parent = _seller(raw.get(parent_col)) if parent_col else ""
    if entity_type == "branch":
        if not parent:
            return None, "branch_parent_missing_or_invalid"
        if parent == seller:
            return None, "branch_parent_self_reference"
    elif parent:
        return None, "non_branch_has_parent"
    record = {
        "seller_identifier": seller,
        "entity_type": entity_type,
        "legal_name": legal_name,
        "registration_status": _clean(raw.get(status_col)) if status_col else "",
        "parent_seller_identifier": parent,
        "source_dataset": source_dataset,
    }
    if set(record) != OUTPUT_KEYS:
        raise AssertionError("INTERNAL_OUTPUT_SURFACE_MISMATCH")
    return record, ""


def _sort_key(record: dict[str, object]) -> tuple[str, str, str, str, str]:
    return (
        str(record["seller_identifier"]),
        str(record["entity_type"]),
        str(record["legal_name"]),
        str(record["parent_seller_identifier"]),
        str(record["registration_status"]),
    )


def _write_chunk(rows: list[dict[str, object]], root: Path, index: int) -> Path:
    rows.sort(key=_sort_key)
    path = root / f"chunk-{index:05d}.ndjson"
    with path.open("wb") as stream:
        for row in rows:
            stream.write(_line(row))
    return path


def _iter_chunk(path: Path) -> Iterator[dict[str, object]]:
    with path.open("r", encoding="utf-8") as stream:
        for raw in stream:
            if raw.strip():
                yield json.loads(raw)


def _merge_chunks(paths: list[Path], output: Path) -> tuple[int, str]:
    iterators = [_iter_chunk(path) for path in paths]
    heap: list[tuple[str, int, dict[str, object]]] = []
    for index, iterator in enumerate(iterators):
        record = next(iterator, None)
        if record is not None:
            heapq.heappush(heap, (str(record["seller_identifier"]), index, record))
    digest = hashlib.sha256()
    count = 0
    with output.open("wb") as stream:
        while heap:
            _, index, record = heapq.heappop(heap)
            encoded = _line(record)
            stream.write(encoded)
            digest.update(encoded)
            count += 1
            following = next(iterators[index], None)
            if following is not None:
                heapq.heappush(heap, (str(following["seller_identifier"]), index, following))
    return count, digest.hexdigest()


def normalize(args: argparse.Namespace) -> dict[str, object]:
    source = Path(args.input_csv)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / "legal_evidence.ndjson"
    rejected = output_dir / "rejected.ndjson"
    source_sha = hashlib.sha256(source.read_bytes()).hexdigest()
    reasons: dict[str, int] = {}
    source_rows = 0
    accepted = 0
    peak_buffer_rows = 0

    with tempfile.TemporaryDirectory(dir=output_dir) as temp_dir, rejected.open("wb") as reject_stream:
        root = Path(temp_dir)
        chunks: list[Path] = []
        buffer: list[dict[str, object]] = []
        with source.open("r", encoding=args.encoding, newline="") as source_stream:
            reader = csv.DictReader(source_stream)
            required = [args.seller_col, args.name_col]
            if args.status_col:
                required.append(args.status_col)
            if args.parent_col:
                required.append(args.parent_col)
            missing = [name for name in required if name not in (reader.fieldnames or [])]
            if missing:
                raise ValueError("MISSING_REQUIRED_COLUMNS:" + ",".join(missing))
            for raw in reader:
                source_rows += 1
                record, reason = _normalize_row(
                    raw,
                    entity_type=args.entity_type,
                    seller_col=args.seller_col,
                    name_col=args.name_col,
                    status_col=args.status_col,
                    parent_col=args.parent_col,
                    source_dataset=args.source_dataset,
                )
                if record is None:
                    reasons[reason] = reasons.get(reason, 0) + 1
                    reject_stream.write(_line({"source_row": source_rows, "reason": reason}))
                    continue
                buffer.append(record)
                accepted += 1
                peak_buffer_rows = max(peak_buffer_rows, len(buffer))
                if len(buffer) >= args.chunk_rows:
                    chunks.append(_write_chunk(buffer, root, len(chunks)))
                    buffer = []
            if buffer:
                chunks.append(_write_chunk(buffer, root, len(chunks)))
        output_count, payload_sha = _merge_chunks(chunks, output)

    if output_count != accepted:
        raise AssertionError("OUTPUT_COUNT_MISMATCH")
    manifest = {
        "schema_version": 1,
        "gate": "P4.20.3-D",
        "entity_type": args.entity_type,
        "source_dataset": args.source_dataset,
        "dataset_id": args.dataset_id,
        "source_url": args.source_url,
        "source_date": args.source_date,
        "license": args.license,
        "source_file_sha256": source_sha,
        "source_row_count": source_rows,
        "accepted_row_count": accepted,
        "rejected_row_count": source_rows - accepted,
        "rejection_reasons": dict(sorted(reasons.items())),
        "payload_sha256": payload_sha,
        "chunk_row_limit": args.chunk_rows,
        "peak_buffer_rows": peak_buffer_rows,
        "responsible_person_payload_emitted": False,
        "merchant_name_inference_used": False,
        "final_mobile_registry": False,
    }
    (output_dir / "normalization_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print("P4_20_3_LEGAL_DATASET_NORMALIZATION=PASS")
    print(json.dumps(manifest, ensure_ascii=False, sort_keys=True))
    return manifest


def self_test() -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        root = Path(temp_dir)
        source = root / "branch.csv"
        source.write_text(
            "公司統一編號,分公司統一編號,分公司名稱,分公司狀態,分公司經理姓名\n"
            "22853565,31655572,富達零售股份有限公司晶技門市,01,敏感欄位不得輸出\n",
            encoding="utf-8",
        )
        args = argparse.Namespace(
            input_csv=str(source),
            output_dir=str(root / "out"),
            entity_type="branch",
            seller_col="分公司統一編號",
            name_col="分公司名稱",
            status_col="分公司狀態",
            parent_col="公司統一編號",
            source_dataset="data.gov.tw:32086",
            dataset_id="32086",
            source_url="https://data.gov.tw/dataset/32086",
            source_date="2026-08-02",
            license=LICENSE,
            encoding="utf-8",
            chunk_rows=1,
        )
        normalize(args)
        row = json.loads((root / "out" / "legal_evidence.ndjson").read_text(encoding="utf-8"))
        assert set(row) == OUTPUT_KEYS
        assert row["seller_identifier"] == "31655572"
        assert row["parent_seller_identifier"] == "22853565"
        assert "分公司經理姓名" not in row
    print("P4_20_3_LEGAL_DATASET_NORMALIZER_SELFTEST=PASS")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_csv", nargs="?")
    parser.add_argument("output_dir", nargs="?")
    parser.add_argument("--entity-type", choices=["company", "business", "branch"])
    parser.add_argument("--seller-col")
    parser.add_argument("--name-col")
    parser.add_argument("--status-col", default="")
    parser.add_argument("--parent-col", default="")
    parser.add_argument("--source-dataset")
    parser.add_argument("--dataset-id", default="")
    parser.add_argument("--source-url", default="")
    parser.add_argument("--source-date", default="")
    parser.add_argument("--license", default=LICENSE)
    parser.add_argument("--encoding", default="utf-8-sig")
    parser.add_argument("--chunk-rows", type=int, default=50000)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    required = [
        "input_csv",
        "output_dir",
        "entity_type",
        "seller_col",
        "name_col",
        "source_dataset",
        "source_url",
        "source_date",
    ]
    missing = [name for name in required if not getattr(args, name)]
    if missing:
        parser.error("missing required arguments: " + ",".join(missing))
    if args.entity_type == "branch" and not args.parent_col:
        parser.error("--parent-col is required for branch")
    if args.chunk_rows < 1:
        parser.error("--chunk-rows must be >= 1")
    normalize(args)


if __name__ == "__main__":
    main()
