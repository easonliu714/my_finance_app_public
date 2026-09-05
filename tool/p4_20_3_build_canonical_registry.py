#!/usr/bin/env python3
"""P4.20.3 Gate E: deterministic nationwide canonical entity merge.

Consumes two seller-ID-sorted privacy-reduced entity streams:
* FIA ready entities from bounded staging; and
* GCIS-enriched entities from Gate D reconciliation.

The final uniqueness authority is seller_identifier only (not seller|entity_type).
Any cross-stream duplicate or cross-type contradiction fails closed. Branch
parent-child closure is verified after the streaming merge using a bounded
on-disk seller index, so nationwide input does not need to be retained in RAM.

Responsible-person / manager payload is structurally impossible because input
and output surfaces are exact-key validated.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sqlite3
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator

SELLER_RE = re.compile(r"^\d{8}$")
ALLOWED_ENTITY_TYPES = frozenset({"company", "business", "branch"})
ENTITY_KEYS = frozenset({
    "record_type",
    "seller_identifier",
    "entity_type",
    "legal_name",
    "registration_status",
    "parent_seller_identifier",
    "source_dataset",
})
MAX_LINE_BYTES = 64 * 1024


def _canonical_line(record: dict[str, object]) -> bytes:
    return (
        json.dumps(record, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        + "\n"
    ).encode("utf-8")


def _clean(value: object) -> str:
    return str(value or "").strip()


def _seller(value: object) -> str:
    value = _clean(value)
    return value if SELLER_RE.fullmatch(value) else ""


def _normalize_entity(
    record: object, *, path: Path, line_number: int
) -> dict[str, str]:
    if not isinstance(record, dict) or frozenset(record) != ENTITY_KEYS:
        raise RuntimeError(f"ENTITY_SURFACE_MISMATCH:{path.name}:{line_number}")

    if record.get("record_type") != "entity":
        raise RuntimeError(f"ENTITY_RECORD_TYPE_INVALID:{path.name}:{line_number}")

    seller = _seller(record.get("seller_identifier"))
    if not seller:
        raise RuntimeError(f"ENTITY_SELLER_INVALID:{path.name}:{line_number}")

    entity_type = _clean(record.get("entity_type")).lower()
    if entity_type not in ALLOWED_ENTITY_TYPES:
        raise RuntimeError(f"ENTITY_TYPE_INVALID:{path.name}:{line_number}")

    legal_name = _clean(record.get("legal_name"))
    if not legal_name:
        raise RuntimeError(f"ENTITY_LEGAL_NAME_REQUIRED:{path.name}:{line_number}")

    registration_status = _clean(record.get("registration_status"))
    if not registration_status:
        raise RuntimeError(
            f"ENTITY_REGISTRATION_STATUS_REQUIRED:{path.name}:{line_number}"
        )

    parent = _seller(record.get("parent_seller_identifier"))
    raw_parent = _clean(record.get("parent_seller_identifier"))
    if raw_parent and not parent:
        raise RuntimeError(f"ENTITY_PARENT_INVALID:{path.name}:{line_number}")

    if entity_type == "branch":
        if not parent:
            raise RuntimeError(f"BRANCH_PARENT_REQUIRED:{path.name}:{line_number}")
        if parent == seller:
            raise RuntimeError(f"BRANCH_PARENT_SELF_REFERENCE:{path.name}:{line_number}")
    elif parent:
        raise RuntimeError(f"NON_BRANCH_PARENT_FORBIDDEN:{path.name}:{line_number}")

    source_dataset = _clean(record.get("source_dataset"))
    if not source_dataset:
        raise RuntimeError(f"ENTITY_SOURCE_DATASET_REQUIRED:{path.name}:{line_number}")

    return {
        "record_type": "entity",
        "seller_identifier": seller,
        "entity_type": entity_type,
        "legal_name": legal_name,
        "registration_status": registration_status,
        "parent_seller_identifier": parent,
        "source_dataset": source_dataset,
    }


def _iter_entities(path: Path) -> Iterator[dict[str, str]]:
    previous = ""
    with path.open("rb") as stream:
        for line_number, raw in enumerate(stream, 1):
            if len(raw) > MAX_LINE_BYTES:
                raise RuntimeError(f"ENTITY_LINE_TOO_LARGE:{path.name}:{line_number}")
            if not raw.strip():
                continue
            try:
                record = json.loads(raw)
            except json.JSONDecodeError as exc:
                raise RuntimeError(
                    f"ENTITY_JSON_INVALID:{path.name}:{line_number}"
                ) from exc
            entity = _normalize_entity(record, path=path, line_number=line_number)
            seller = entity["seller_identifier"]
            if previous and seller <= previous:
                reason = "DUPLICATE" if seller == previous else "NOT_SORTED"
                raise RuntimeError(f"ENTITY_INPUT_{reason}:{path.name}:{line_number}")
            previous = seller
            yield entity


@dataclass
class MergeStats:
    ready_count: int = 0
    enriched_count: int = 0
    canonical_count: int = 0
    company_count: int = 0
    business_count: int = 0
    branch_count: int = 0


def _next(iterator: Iterator[dict[str, str]]) -> dict[str, str] | None:
    return next(iterator, None)


def _init_index(path: Path) -> sqlite3.Connection:
    if path.exists():
        path.unlink()
    conn = sqlite3.connect(path)
    conn.execute("PRAGMA journal_mode=OFF")
    conn.execute("PRAGMA synchronous=OFF")
    conn.execute("PRAGMA temp_store=FILE")
    conn.execute(
        """
        CREATE TABLE canonical_entity (
          seller_identifier TEXT PRIMARY KEY,
          entity_type TEXT NOT NULL,
          parent_seller_identifier TEXT NOT NULL
        ) WITHOUT ROWID
        """
    )
    return conn


def build_canonical_registry(
    ready_path: Path,
    enriched_path: Path,
    output_path: Path,
    summary_path: Path,
) -> dict[str, object]:
    """Streaming two-way merge with seller-only uniqueness and parent closure."""

    output_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    index_path = output_path.with_suffix(output_path.suffix + ".index.sqlite")
    temp_output = output_path.with_suffix(output_path.suffix + ".partial")
    for path in (temp_output, index_path):
        if path.exists():
            path.unlink()

    ready_iter = _iter_entities(ready_path)
    enriched_iter = _iter_entities(enriched_path)
    ready = _next(ready_iter)
    enriched = _next(enriched_iter)
    stats = MergeStats()
    payload_sha = hashlib.sha256()
    conn = _init_index(index_path)

    try:
        with temp_output.open("wb") as out:
            while ready is not None or enriched is not None:
                if ready is not None and enriched is not None:
                    ready_seller = ready["seller_identifier"]
                    enriched_seller = enriched["seller_identifier"]
                    if ready_seller == enriched_seller:
                        raise RuntimeError(
                            "CROSS_STREAM_DUPLICATE_SELLER_IDENTIFIER:"
                            + ready_seller
                        )
                    if ready_seller < enriched_seller:
                        entity = ready
                        stats.ready_count += 1
                        ready = _next(ready_iter)
                    else:
                        entity = enriched
                        stats.enriched_count += 1
                        enriched = _next(enriched_iter)
                elif ready is not None:
                    entity = ready
                    stats.ready_count += 1
                    ready = _next(ready_iter)
                else:
                    assert enriched is not None
                    entity = enriched
                    stats.enriched_count += 1
                    enriched = _next(enriched_iter)

                encoded = _canonical_line(entity)
                out.write(encoded)
                payload_sha.update(encoded)
                stats.canonical_count += 1

                entity_type = entity["entity_type"]
                if entity_type == "company":
                    stats.company_count += 1
                elif entity_type == "business":
                    stats.business_count += 1
                elif entity_type == "branch":
                    stats.branch_count += 1
                else:
                    raise AssertionError("UNREACHABLE_ENTITY_TYPE")

                try:
                    conn.execute(
                        """
                        INSERT INTO canonical_entity(
                          seller_identifier, entity_type, parent_seller_identifier
                        ) VALUES (?, ?, ?)
                        """,
                        (
                            entity["seller_identifier"],
                            entity_type,
                            entity["parent_seller_identifier"],
                        ),
                    )
                except sqlite3.IntegrityError as exc:
                    raise RuntimeError(
                        "CANONICAL_DUPLICATE_SELLER_IDENTIFIER:"
                        + entity["seller_identifier"]
                    ) from exc

        conn.commit()

        missing_parent = conn.execute(
            """
            SELECT child.seller_identifier, child.parent_seller_identifier
              FROM canonical_entity AS child
         LEFT JOIN canonical_entity AS parent
                ON parent.seller_identifier = child.parent_seller_identifier
             WHERE child.entity_type = 'branch'
               AND parent.seller_identifier IS NULL
             LIMIT 1
            """
        ).fetchone()
        if missing_parent is not None:
            raise RuntimeError(
                "BRANCH_PARENT_NOT_IN_CANONICAL_REGISTRY:"
                f"{missing_parent[0]}->{missing_parent[1]}"
            )

        invalid_parent_type = conn.execute(
            """
            SELECT child.seller_identifier, parent.entity_type
              FROM canonical_entity AS child
              JOIN canonical_entity AS parent
                ON parent.seller_identifier = child.parent_seller_identifier
             WHERE child.entity_type = 'branch'
               AND parent.entity_type = 'branch'
             LIMIT 1
            """
        ).fetchone()
        if invalid_parent_type is not None:
            raise RuntimeError(
                "BRANCH_PARENT_CANNOT_BE_BRANCH:"
                f"{invalid_parent_type[0]}->{invalid_parent_type[1]}"
            )

        if stats.canonical_count != stats.ready_count + stats.enriched_count:
            raise AssertionError("CANONICAL_COUNT_PARTITION_MISMATCH")
        if stats.canonical_count != (
            stats.company_count + stats.business_count + stats.branch_count
        ):
            raise AssertionError("CANONICAL_TYPE_COUNT_MISMATCH")

        summary: dict[str, object] = {
            "schema_version": 1,
            "gate": "P4.20.3-E",
            "coverage": "nationwide_candidate",
            "final_mobile_registry": False,
            "canonical_uniqueness_key": "seller_identifier",
            "ready_entity_count": stats.ready_count,
            "enriched_entity_count": stats.enriched_count,
            "canonical_entity_count": stats.canonical_count,
            "company_count": stats.company_count,
            "business_count": stats.business_count,
            "branch_count": stats.branch_count,
            "canonical_entities_sha256": payload_sha.hexdigest(),
            "canonical_entities_bytes": temp_output.stat().st_size,
            "branch_parent_closure": True,
            "responsible_person_payload_emitted": False,
            "validation_subset": False,
        }
        temp_output.replace(output_path)
        summary_path.write_text(
            json.dumps(
                summary,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            )
            + "\n",
            encoding="utf-8",
        )
        return summary
    except Exception:
        if temp_output.exists():
            temp_output.unlink()
        if output_path.exists():
            output_path.unlink()
        if summary_path.exists():
            summary_path.unlink()
        raise
    finally:
        conn.close()
        if index_path.exists():
            index_path.unlink()


def _write(path: Path, records: list[dict[str, object]]) -> None:
    path.write_bytes(b"".join(_canonical_line(record) for record in records))


def _entity(
    seller: str,
    entity_type: str,
    name: str,
    *,
    parent: str = "",
    source: str = "FIXTURE",
) -> dict[str, object]:
    return {
        "record_type": "entity",
        "seller_identifier": seller,
        "entity_type": entity_type,
        "legal_name": name,
        "registration_status": "active",
        "parent_seller_identifier": parent,
        "source_dataset": source,
    }


def self_test() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        ready = root / "ready.ndjson"
        enriched = root / "enriched.ndjson"
        output = root / "canonical.ndjson"
        summary = root / "summary.json"

        _write(
            ready,
            [
                _entity("11111111", "company", "甲公司"),
                _entity("22222222", "branch", "甲分店", parent="11111111"),
                _entity("44444444", "business", "丁商號"),
            ],
        )
        _write(
            enriched,
            [_entity("33333333", "business", "丙商號", source="FIA+GCIS")],
        )
        result = build_canonical_registry(ready, enriched, output, summary)
        assert result["canonical_entity_count"] == 4
        assert result["company_count"] == 1
        assert result["business_count"] == 2
        assert result["branch_count"] == 1
        assert result["branch_parent_closure"] is True
        sellers = [
            json.loads(line)["seller_identifier"]
            for line in output.read_text(encoding="utf-8").splitlines()
        ]
        assert sellers == ["11111111", "22222222", "33333333", "44444444"]

        # Same seller across input streams must fail even when facts match.
        _write(ready, [_entity("11111111", "company", "甲公司")])
        _write(enriched, [_entity("11111111", "company", "甲公司")])
        try:
            build_canonical_registry(ready, enriched, output, summary)
            raise AssertionError("EXPECTED_CROSS_STREAM_DUPLICATE_HOLD")
        except RuntimeError as exc:
            assert str(exc).startswith("CROSS_STREAM_DUPLICATE_SELLER_IDENTIFIER:")

        # Cross-type contradiction is necessarily covered by the same seller-only gate.
        _write(ready, [_entity("11111111", "company", "甲公司")])
        _write(enriched, [_entity("11111111", "business", "甲商號")])
        try:
            build_canonical_registry(ready, enriched, output, summary)
            raise AssertionError("EXPECTED_CROSS_TYPE_DUPLICATE_HOLD")
        except RuntimeError as exc:
            assert str(exc).startswith("CROSS_STREAM_DUPLICATE_SELLER_IDENTIFIER:")

        # A branch may not survive if its parent is absent from the final registry.
        _write(ready, [_entity("22222222", "branch", "孤兒分店", parent="11111111")])
        _write(enriched, [])
        try:
            build_canonical_registry(ready, enriched, output, summary)
            raise AssertionError("EXPECTED_MISSING_PARENT_HOLD")
        except RuntimeError as exc:
            assert str(exc).startswith("BRANCH_PARENT_NOT_IN_CANONICAL_REGISTRY:")

        # A branch cannot be another branch's canonical parent.
        _write(
            ready,
            [
                _entity("11111111", "branch", "父分店", parent="33333333"),
                _entity("22222222", "branch", "子分店", parent="11111111"),
                _entity("33333333", "company", "總公司"),
            ],
        )
        _write(enriched, [])
        try:
            build_canonical_registry(ready, enriched, output, summary)
            raise AssertionError("EXPECTED_BRANCH_PARENT_TYPE_HOLD")
        except RuntimeError as exc:
            assert str(exc).startswith("BRANCH_PARENT_CANNOT_BE_BRANCH:")

    print("P4_20_3_CANONICAL_NATIONWIDE_MERGE_SELFTEST=PASS")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("ready", nargs="?", type=Path)
    parser.add_argument("enriched", nargs="?", type=Path)
    parser.add_argument("output", nargs="?", type=Path)
    parser.add_argument("summary", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return
    if None in (args.ready, args.enriched, args.output, args.summary):
        parser.error(
            "ready, enriched, output and summary are required unless --self-test is used"
        )
    result = build_canonical_registry(
        args.ready, args.enriched, args.output, args.summary
    )
    print("P4_20_3_CANONICAL_NATIONWIDE_MERGE=PASS")
    print(f"CANONICAL_ENTITY_COUNT={result['canonical_entity_count']}")
    print(f"CANONICAL_ENTITIES_SHA256={result['canonical_entities_sha256']}")


if __name__ == "__main__":
    main()
