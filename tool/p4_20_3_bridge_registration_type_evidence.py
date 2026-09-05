#!/usr/bin/env python3
"""P4.20.3 Gate D bridge from paired GCIS type evidence to legal evidence.

Consumes the privacy-reduced FIA legal-enrichment queue plus the exact seller-set
GCIS registration-type evidence produced by p4_20_3_acquire_gcis_registration_type.py.
Only unambiguous Company/Business classifications are materialized. Branch
classification is fail-closed unless an authoritative parent identity exists;
this bridge has no parent-bearing source, so branch rows are HOLD rather than
inventing a parent. FIA legal_name is an official tax-registration literal, not
merchant-name inference.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import tempfile
from pathlib import Path
from typing import Iterator

QUEUE_KEYS = {
    "seller_identifier",
    "legal_name",
    "organization_type",
    "uses_uniform_invoice",
    "source_dataset",
}
TYPE_KEYS = {
    "seller_identifier",
    "official_types",
    "official_exists_values",
    "official_year_values",
    "source_dataset",
}
LEGAL_KEYS = {
    "seller_identifier",
    "entity_type",
    "legal_name",
    "registration_status",
    "parent_seller_identifier",
    "source_dataset",
}
TYPE_MAP = {
    "COMPANY": "company",
    "公司": "company",
    "BUSINESS": "business",
    "商業": "business",
    "BRANCH": "branch",
    "分公司": "branch",
}


def _seller(value: object) -> str:
    digits = "".join(ch for ch in str(value or "") if ch.isdigit())
    return digits if len(digits) == 8 else ""


def _clean(value: object) -> str:
    return str(value or "").strip()


def _line(record: dict[str, object]) -> bytes:
    return (json.dumps(record, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def _iter_exact(path: Path, keys: set[str]) -> Iterator[dict[str, object]]:
    previous = ""
    seen: set[str] = set()
    with path.open("r", encoding="utf-8-sig") as stream:
        for line_number, raw in enumerate(stream, 1):
            if not raw.strip():
                continue
            row = json.loads(raw)
            if not isinstance(row, dict) or set(row) != keys:
                raise ValueError(f"PAYLOAD_SURFACE_MISMATCH:{path.name}:{line_number}")
            seller = _seller(row.get("seller_identifier"))
            if not seller:
                raise ValueError(f"INVALID_SELLER_IDENTIFIER:{path.name}:{line_number}")
            if seller in seen:
                raise ValueError(f"DUPLICATE_SELLER_IDENTIFIER:{path.name}:{seller}")
            if previous and seller < previous:
                raise ValueError(f"INPUT_NOT_SORTED:{path.name}:{line_number}")
            previous = seller
            seen.add(seller)
            yield row


def _classification(types: object) -> tuple[str, str]:
    if not isinstance(types, list):
        return "", "official_types_not_list"
    normalized: set[str] = set()
    unknown: set[str] = set()
    for raw in types:
        token = _clean(raw)
        mapped = TYPE_MAP.get(token) or TYPE_MAP.get(token.upper())
        if mapped:
            normalized.add(mapped)
        elif token:
            unknown.add(token)
    if unknown:
        return "", "official_type_unsupported"
    if not normalized:
        return "", "official_type_no_affirmative_match"
    if len(normalized) != 1:
        return "", "official_type_ambiguous"
    entity_type = next(iter(normalized))
    if entity_type == "branch":
        return "", "branch_parent_identity_required"
    return entity_type, ""


def bridge(queue_path: Path, evidence_path: Path, output_dir: Path) -> dict[str, object]:
    queue = list(_iter_exact(queue_path, QUEUE_KEYS))
    evidence = list(_iter_exact(evidence_path, TYPE_KEYS))
    queue_ids = [str(row["seller_identifier"]) for row in queue]
    evidence_ids = [str(row["seller_identifier"]) for row in evidence]
    if queue_ids != evidence_ids:
        raise ValueError("EXACT_SELLER_SET_PARITY_MISMATCH")

    output_dir.mkdir(parents=True, exist_ok=True)
    legal_path = output_dir / "legal_evidence.ndjson"
    unresolved_path = output_dir / "unresolved.ndjson"
    hold_path = output_dir / "hold.ndjson"
    legal_sha = hashlib.sha256()
    classified = unresolved = hold = 0

    with legal_path.open("wb") as legal, unresolved_path.open("wb") as unresolved_stream, hold_path.open("wb") as hold_stream:
        for fia, gcis in zip(queue, evidence, strict=True):
            seller = str(fia["seller_identifier"])
            entity_type, reason = _classification(gcis["official_types"])
            if entity_type:
                legal_name = _clean(fia["legal_name"])
                if not legal_name:
                    raise ValueError(f"FIA_OFFICIAL_LEGAL_NAME_EMPTY:{seller}")
                record = {
                    "seller_identifier": seller,
                    "entity_type": entity_type,
                    "legal_name": legal_name,
                    "registration_status": "",
                    "parent_seller_identifier": "",
                    "source_dataset": f"{_clean(fia['source_dataset'])}+{_clean(gcis['source_dataset'])}",
                }
                if set(record) != LEGAL_KEYS:
                    raise AssertionError("INTERNAL_LEGAL_SURFACE_MISMATCH")
                encoded = _line(record)
                legal.write(encoded)
                legal_sha.update(encoded)
                classified += 1
            elif reason == "official_type_no_affirmative_match":
                unresolved_stream.write(_line({"seller_identifier": seller, "reason": reason}))
                unresolved += 1
            else:
                hold_stream.write(_line({"seller_identifier": seller, "reason": reason}))
                hold += 1

    if classified + unresolved + hold != len(queue):
        raise AssertionError("BRIDGE_PARTITION_MISMATCH")
    manifest = {
        "schema_version": 1,
        "gate": "P4.20.3-D-registration-type-to-legal-evidence",
        "validation_subset": False,
        "queue_seller_count": len(queue),
        "evidence_seller_count": len(evidence),
        "classified_legal_entity_count": classified,
        "unresolved_seller_count": unresolved,
        "hold_seller_count": hold,
        "legal_evidence_payload_sha256": legal_sha.hexdigest(),
        "official_type_exist_pairing_preserved": True,
        "parent_child_identity_preserved": True,
        "branch_without_parent_policy": "HOLD",
        "responsible_person_payload_emitted": False,
        "merchant_name_inference_used": False,
        "mobile_per_invoice_network_lookup": False,
        "final_mobile_registry": False,
    }
    (output_dir / "bridge_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print("P4_20_3_REGISTRATION_TYPE_LEGAL_BRIDGE=PASS")
    print(json.dumps(manifest, ensure_ascii=False, sort_keys=True))
    return manifest


def self_test() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        queue = root / "queue.ndjson"
        evidence = root / "evidence.ndjson"
        queue_rows = [
            {"seller_identifier":"11111111","legal_name":"甲股份有限公司","organization_type":"股份有限公司","uses_uniform_invoice":"Y","source_dataset":"FIA"},
            {"seller_identifier":"22222222","legal_name":"乙商號","organization_type":"獨資","uses_uniform_invoice":"Y","source_dataset":"FIA"},
            {"seller_identifier":"33333333","legal_name":"丙分公司","organization_type":"其他","uses_uniform_invoice":"Y","source_dataset":"FIA"},
            {"seller_identifier":"44444444","legal_name":"丁組織","organization_type":"其他","uses_uniform_invoice":"Y","source_dataset":"FIA"},
        ]
        evidence_rows = [
            {"seller_identifier":"11111111","official_types":["公司"],"official_exists_values":["N","Y"],"official_year_values":["115"],"source_dataset":"GCIS"},
            {"seller_identifier":"22222222","official_types":["BUSINESS"],"official_exists_values":["Y"],"official_year_values":["2026"],"source_dataset":"GCIS"},
            {"seller_identifier":"33333333","official_types":["分公司"],"official_exists_values":["Y"],"official_year_values":["115"],"source_dataset":"GCIS"},
            {"seller_identifier":"44444444","official_types":[],"official_exists_values":["N"],"official_year_values":["115"],"source_dataset":"GCIS"},
        ]
        queue.write_bytes(b"".join(_line(row) for row in queue_rows))
        evidence.write_bytes(b"".join(_line(row) for row in evidence_rows))
        manifest = bridge(queue, evidence, root / "out")
        assert manifest["classified_legal_entity_count"] == 2
        assert manifest["hold_seller_count"] == 1
        assert manifest["unresolved_seller_count"] == 1
        rows = [json.loads(line) for line in (root/"out"/"legal_evidence.ndjson").read_text(encoding="utf-8").splitlines()]
        assert [row["entity_type"] for row in rows] == ["company", "business"]
        assert rows[0]["legal_name"] == "甲股份有限公司"
        assert rows[0]["parent_seller_identifier"] == ""
        hold = json.loads((root/"out"/"hold.ndjson").read_text(encoding="utf-8").strip())
        assert hold["reason"] == "branch_parent_identity_required"
        unresolved = json.loads((root/"out"/"unresolved.ndjson").read_text(encoding="utf-8").strip())
        assert unresolved["reason"] == "official_type_no_affirmative_match"
        assert manifest["validation_subset"] is False
        assert manifest["official_type_exist_pairing_preserved"] is True
        assert manifest["parent_child_identity_preserved"] is True
        assert manifest["responsible_person_payload_emitted"] is False
        assert manifest["merchant_name_inference_used"] is False
        assert manifest["mobile_per_invoice_network_lookup"] is False
    print("P4_20_3_REGISTRATION_TYPE_LEGAL_BRIDGE_SELFTEST=PASS")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("queue", nargs="?", type=Path)
    parser.add_argument("registration_type_evidence", nargs="?", type=Path)
    parser.add_argument("output_dir", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.queue is None or args.registration_type_evidence is None or args.output_dir is None:
        parser.error("queue, registration_type_evidence and output_dir are required unless --self-test is used")
    bridge(args.queue, args.registration_type_evidence, args.output_dir)


if __name__ == "__main__":
    main()
