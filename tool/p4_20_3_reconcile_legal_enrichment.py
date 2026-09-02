#!/usr/bin/env python3
"""P4.20.3 Gate D: deterministic legal-enrichment reconciliation.

Consumes the externally sorted FIA ``enrichment_required.ndjson`` produced by
``p4_20_3_stage_fia_registry.py`` plus an externally sorted GCIS legal
registration evidence stream.  It emits only privacy-reduced canonical mobile
registry entities; responsible-person / manager payload is neither accepted nor
serialized.

The reconciler is deliberately fail closed:
* inputs must be sorted by seller identifier;
* duplicate GCIS rows collapse only when their canonical legal facts agree;
* semantic disagreement becomes HOLD;
* a parentless FIA residual row cannot be promoted to ``branch`` without an
  authoritative parent identifier;
* missing GCIS evidence remains unresolved rather than being guessed from the
  merchant name or FIA residual organization label.

Memory is O(size of one seller-ID duplicate group), not O(nationwide rows).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator, TextIO

ALLOWED_ENTITY_TYPES = {"company", "business", "branch"}
QUEUE_KEYS = {
    "seller_identifier",
    "legal_name",
    "organization_type",
    "uses_uniform_invoice",
    "source_dataset",
}
GCIS_KEYS = {
    "seller_identifier",
    "entity_type",
    "legal_name",
    "registration_status",
    "parent_seller_identifier",
    "source_dataset",
}
ENTITY_KEYS = {
    "record_type",
    "seller_identifier",
    "entity_type",
    "legal_name",
    "registration_status",
    "parent_seller_identifier",
    "source_dataset",
}


def _digits(value: object) -> str:
    return "".join(ch for ch in str(value or "") if ch.isdigit())


def _clean(value: object) -> str:
    return str(value or "").strip()


def _seller(value: object) -> str:
    digits = _digits(value)
    return digits if len(digits) == 8 else ""


def _json_line(record: dict[str, object]) -> bytes:
    return (
        json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n"
    ).encode("utf-8")


def _iter_ndjson(path: Path, allowed_keys: set[str]) -> Iterator[dict[str, object]]:
    previous = ""
    with path.open("r", encoding="utf-8") as stream:
        for line_number, raw in enumerate(stream, 1):
            if not raw.strip():
                continue
            record = json.loads(raw)
            if not isinstance(record, dict) or set(record) != allowed_keys:
                raise ValueError(f"PAYLOAD_SURFACE_MISMATCH:{path.name}:{line_number}")
            seller = _seller(record.get("seller_identifier"))
            if not seller:
                raise ValueError(f"INVALID_SELLER_IDENTIFIER:{path.name}:{line_number}")
            if previous and seller < previous:
                raise ValueError(f"INPUT_NOT_SORTED:{path.name}:{line_number}")
            previous = seller
            yield record


def _group_by_seller(
    records: Iterable[dict[str, object]],
) -> Iterator[tuple[str, list[dict[str, object]]]]:
    current = ""
    group: list[dict[str, object]] = []
    for record in records:
        seller = _seller(record["seller_identifier"])
        if current and seller != current:
            yield current, group
            group = []
        current = seller
        group.append(record)
    if group:
        yield current, group


def _canonical_gcis_facts(record: dict[str, object]) -> tuple[str, str, str, str]:
    entity_type = _clean(record["entity_type"]).lower()
    legal_name = _clean(record["legal_name"])
    parent = _seller(record["parent_seller_identifier"])
    status = _clean(record["registration_status"])
    return entity_type, legal_name, parent, status


def _resolve_gcis_group(
    seller: str,
    group: list[dict[str, object]],
) -> tuple[dict[str, object] | None, str]:
    facts = {_canonical_gcis_facts(row) for row in group}
    if len(facts) != 1:
        return None, "gcis_duplicate_semantic_disagreement"

    entity_type, legal_name, parent, status = next(iter(facts))
    if entity_type not in ALLOWED_ENTITY_TYPES:
        return None, "gcis_entity_type_not_mobile_supported"
    if not legal_name:
        return None, "gcis_legal_name_empty"
    if entity_type == "branch":
        if not parent:
            return None, "gcis_branch_parent_missing"
        if parent == seller:
            return None, "gcis_branch_parent_self_reference"
    elif parent:
        return None, "gcis_non_branch_has_parent"

    sources = sorted({_clean(row["source_dataset"]) for row in group if _clean(row["source_dataset"])})
    if not sources:
        return None, "gcis_source_dataset_empty"

    return {
        "seller_identifier": seller,
        "entity_type": entity_type,
        "legal_name": legal_name,
        "registration_status": status,
        "parent_seller_identifier": parent,
        "source_dataset": "+".join(sources),
    }, ""


@dataclass
class ReconcileStats:
    queue_rows: int = 0
    queue_sellers: int = 0
    gcis_rows: int = 0
    gcis_sellers: int = 0
    enriched: int = 0
    unresolved: int = 0
    hold: int = 0
    orphan_gcis_sellers: int = 0
    max_queue_duplicate_group: int = 0
    max_gcis_duplicate_group: int = 0


def reconcile(queue_path: Path, gcis_path: Path, output_dir: Path) -> dict[str, object]:
    output_dir.mkdir(parents=True, exist_ok=True)
    entity_path = output_dir / "enriched_entities.ndjson"
    unresolved_path = output_dir / "unresolved.ndjson"
    hold_path = output_dir / "hold.ndjson"
    summary_path = output_dir / "reconciliation_summary.json"

    stats = ReconcileStats()
    entity_sha = hashlib.sha256()

    queue_iter = _group_by_seller(_iter_ndjson(queue_path, QUEUE_KEYS))
    gcis_iter = _group_by_seller(_iter_ndjson(gcis_path, GCIS_KEYS))
    q = next(queue_iter, None)
    g = next(gcis_iter, None)

    with (
        entity_path.open("wb") as entities,
        unresolved_path.open("wb") as unresolved,
        hold_path.open("wb") as holds,
    ):
        while q is not None or g is not None:
            if q is None:
                seller, g_rows = g  # type: ignore[misc]
                stats.gcis_rows += len(g_rows)
                stats.gcis_sellers += 1
                stats.orphan_gcis_sellers += 1
                stats.max_gcis_duplicate_group = max(stats.max_gcis_duplicate_group, len(g_rows))
                g = next(gcis_iter, None)
                continue

            q_seller, q_rows = q
            stats.queue_rows += len(q_rows)
            stats.queue_sellers += 1
            stats.max_queue_duplicate_group = max(stats.max_queue_duplicate_group, len(q_rows))

            if len(q_rows) != 1:
                payload = {
                    "seller_identifier": q_seller,
                    "reason": "fia_enrichment_queue_duplicate_seller",
                    "queue_row_count": len(q_rows),
                }
                holds.write(_json_line(payload))
                stats.hold += 1
                q = next(queue_iter, None)
                continue

            while g is not None and g[0] < q_seller:
                _, g_rows = g
                stats.gcis_rows += len(g_rows)
                stats.gcis_sellers += 1
                stats.orphan_gcis_sellers += 1
                stats.max_gcis_duplicate_group = max(stats.max_gcis_duplicate_group, len(g_rows))
                g = next(gcis_iter, None)

            if g is None or g[0] > q_seller:
                row = q_rows[0]
                unresolved.write(_json_line({
                    "seller_identifier": q_seller,
                    "legal_name": _clean(row["legal_name"]),
                    "organization_type": _clean(row["organization_type"]),
                    "reason": "gcis_legal_enrichment_missing",
                }))
                stats.unresolved += 1
                q = next(queue_iter, None)
                continue

            _, g_rows = g
            stats.gcis_rows += len(g_rows)
            stats.gcis_sellers += 1
            stats.max_gcis_duplicate_group = max(stats.max_gcis_duplicate_group, len(g_rows))
            resolved, reason = _resolve_gcis_group(q_seller, g_rows)
            if resolved is None:
                holds.write(_json_line({
                    "seller_identifier": q_seller,
                    "reason": reason,
                    "gcis_row_count": len(g_rows),
                }))
                stats.hold += 1
            else:
                fia = q_rows[0]
                fia_name = _clean(fia["legal_name"])
                gcis_name = _clean(resolved["legal_name"])
                # Names can legitimately differ between tax registration and legal
                # registration.  Preserve GCIS as the canonical legal name while
                # retaining source provenance; never infer a type from either name.
                source = "+".join(filter(None, [
                    _clean(fia["source_dataset"]),
                    _clean(resolved["source_dataset"]),
                ]))
                entity = {
                    "record_type": "entity",
                    "seller_identifier": q_seller,
                    "entity_type": resolved["entity_type"],
                    "legal_name": gcis_name or fia_name,
                    "registration_status": resolved["registration_status"],
                    "parent_seller_identifier": resolved["parent_seller_identifier"],
                    "source_dataset": source,
                }
                if set(entity) != ENTITY_KEYS:
                    raise AssertionError("INTERNAL_ENTITY_SURFACE_MISMATCH")
                encoded = _json_line(entity)
                entities.write(encoded)
                entity_sha.update(encoded)
                stats.enriched += 1

            q = next(queue_iter, None)
            g = next(gcis_iter, None)

    if stats.enriched + stats.unresolved + stats.hold != stats.queue_sellers:
        raise AssertionError("RECONCILIATION_PARTITION_MISMATCH")

    summary = {
        "schema_version": 1,
        "gate": "P4.20.3-D",
        "queue_row_count": stats.queue_rows,
        "queue_seller_count": stats.queue_sellers,
        "gcis_row_count_consumed": stats.gcis_rows,
        "gcis_seller_count_consumed": stats.gcis_sellers,
        "enriched_entity_count": stats.enriched,
        "unresolved_seller_count": stats.unresolved,
        "hold_seller_count": stats.hold,
        "orphan_gcis_seller_count": stats.orphan_gcis_sellers,
        "max_queue_duplicate_group": stats.max_queue_duplicate_group,
        "max_gcis_duplicate_group": stats.max_gcis_duplicate_group,
        "enriched_entity_payload_sha256": entity_sha.hexdigest(),
        "responsible_person_payload_emitted": False,
        "merchant_name_inference_used": False,
        "final_mobile_registry": False,
        "coverage_claim": "legal_enrichment_reconciliation_only",
    }
    summary_path.write_text(
        json.dumps(summary, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    return summary


def _write_lines(path: Path, rows: list[dict[str, object]]) -> None:
    path.write_bytes(b"".join(_json_line(row) for row in rows))


def self_test() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        queue = root / "queue.ndjson"
        gcis = root / "gcis.ndjson"
        out = root / "out"
        queue_rows = [
            {
                "seller_identifier": "11111111",
                "legal_name": "甲合作社",
                "organization_type": "合作社",
                "uses_uniform_invoice": "Y",
                "source_dataset": "FIA",
            },
            {
                "seller_identifier": "22222222",
                "legal_name": "乙有限合夥",
                "organization_type": "有限合夥",
                "uses_uniform_invoice": "Y",
                "source_dataset": "FIA",
            },
            {
                "seller_identifier": "33333333",
                "legal_name": "丙辦事處",
                "organization_type": "外國公司在台之辦事處",
                "uses_uniform_invoice": "Y",
                "source_dataset": "FIA",
            },
        ]
        gcis_rows = [
            {
                "seller_identifier": "11111111",
                "entity_type": "business",
                "legal_name": "甲合作社",
                "registration_status": "核准設立",
                "parent_seller_identifier": "",
                "source_dataset": "GCIS_A",
            },
            # Identical canonical facts from another source/page must collapse.
            {
                "seller_identifier": "11111111",
                "entity_type": "business",
                "legal_name": "甲合作社",
                "registration_status": "核准設立",
                "parent_seller_identifier": "",
                "source_dataset": "GCIS_B",
            },
            # Semantic disagreement must HOLD.
            {
                "seller_identifier": "22222222",
                "entity_type": "company",
                "legal_name": "乙有限合夥",
                "registration_status": "核准設立",
                "parent_seller_identifier": "",
                "source_dataset": "GCIS_A",
            },
            {
                "seller_identifier": "22222222",
                "entity_type": "business",
                "legal_name": "乙有限合夥",
                "registration_status": "核准設立",
                "parent_seller_identifier": "",
                "source_dataset": "GCIS_B",
            },
        ]
        _write_lines(queue, queue_rows)
        _write_lines(gcis, gcis_rows)
        summary = reconcile(queue, gcis, out)
        assert summary["queue_seller_count"] == 3
        assert summary["enriched_entity_count"] == 1
        assert summary["hold_seller_count"] == 1
        assert summary["unresolved_seller_count"] == 1
        entity = json.loads((out / "enriched_entities.ndjson").read_text().strip())
        assert entity["seller_identifier"] == "11111111"
        assert entity["entity_type"] == "business"
        assert entity["source_dataset"] == "FIA+GCIS_A+GCIS_B"
        hold = json.loads((out / "hold.ndjson").read_text().strip())
        assert hold["reason"] == "gcis_duplicate_semantic_disagreement"
        unresolved = json.loads((out / "unresolved.ndjson").read_text().strip())
        assert unresolved["seller_identifier"] == "33333333"
    print("P4_20_3_LEGAL_ENRICHMENT_RECONCILER_SELFTEST=PASS")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("queue", nargs="?", type=Path)
    parser.add_argument("gcis", nargs="?", type=Path)
    parser.add_argument("output", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.queue is None or args.gcis is None or args.output is None:
        parser.error("queue, gcis and output are required unless --self-test is used")
    summary = reconcile(args.queue, args.gcis, args.output)
    print("P4_20_3_LEGAL_ENRICHMENT_RECONCILIATION=PASS")
    print(f"QUEUE_SELLERS={summary['queue_seller_count']}")
    print(f"ENRICHED={summary['enriched_entity_count']}")
    print(f"UNRESOLVED={summary['unresolved_seller_count']}")
    print(f"HOLD={summary['hold_seller_count']}")
    print(f"ENRICHED_SHA256={summary['enriched_entity_payload_sha256']}")


if __name__ == "__main__":
    main()
