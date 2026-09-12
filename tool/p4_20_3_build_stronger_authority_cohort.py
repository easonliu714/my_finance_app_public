#!/usr/bin/env python3
"""Build deterministic, privacy-reduced P4.20.3 stronger-authority cohorts.

Consumes the published bridge/hold.ndjson authority queue plus bridge_manifest.json.
The input bytes must match the manifest-declared count and SHA-256. Output cohorts
are partitioned by authority reason without broadening the payload surface, so
subsequent GCIS parent/type authority acquisition can be bounded to the exact
SHA-bound seller set instead of rescanning the full residual cohort.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import tempfile
from pathlib import Path
from typing import Iterator

AUTHORITY_KEYS = {"seller_identifier", "candidate_entity_types", "reason"}
REASON_TO_FILE = {
    "branch_parent_identity_required": "branch_parent_required.ndjson",
    "official_type_ambiguous_requires_authority": "ambiguous_type_required.ndjson",
    "official_type_unsupported_requires_authority": "unsupported_type_required.ndjson",
    "official_types_not_list": "unsupported_type_required.ndjson",
}


def _seller(value: object) -> str:
    digits = "".join(ch for ch in str(value or "") if ch.isdigit())
    return digits if len(digits) == 8 else ""


def _line(record: dict[str, object]) -> bytes:
    return (
        json.dumps(record, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        + "\n"
    ).encode("utf-8")


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _iter_authority(path: Path) -> Iterator[dict[str, object]]:
    previous = ""
    seen: set[str] = set()
    with path.open("r", encoding="utf-8-sig") as stream:
        for line_number, raw in enumerate(stream, 1):
            if not raw.strip():
                continue
            row = json.loads(raw)
            if not isinstance(row, dict) or set(row) != AUTHORITY_KEYS:
                raise ValueError(f"AUTHORITY_SURFACE_MISMATCH:{line_number}")
            seller = _seller(row.get("seller_identifier"))
            if not seller:
                raise ValueError(f"INVALID_SELLER_IDENTIFIER:{line_number}")
            if seller in seen:
                raise ValueError(f"DUPLICATE_SELLER_IDENTIFIER:{seller}")
            if previous and seller < previous:
                raise ValueError(f"AUTHORITY_INPUT_NOT_SORTED:{line_number}")
            candidates = row.get("candidate_entity_types")
            if (
                not isinstance(candidates, list)
                or candidates != sorted(set(str(v) for v in candidates))
            ):
                raise ValueError(f"CANDIDATE_TYPES_NOT_CANONICAL:{seller}")
            reason = str(row.get("reason") or "")
            if reason not in REASON_TO_FILE:
                raise ValueError(f"UNSUPPORTED_AUTHORITY_REASON:{seller}:{reason}")
            previous = seller
            seen.add(seller)
            yield row


def build(
    authority_path: Path, bridge_manifest_path: Path, output_dir: Path
) -> dict[str, object]:
    manifest = json.loads(bridge_manifest_path.read_text(encoding="utf-8"))
    if manifest.get("validation_subset") is not False:
        raise ValueError("VALIDATION_SUBSET_MUST_BE_FALSE")
    if manifest.get("hold_is_authority_required_queue") is not True:
        raise ValueError("PUBLISHED_HOLD_NOT_AUTHORITY_QUEUE")
    if manifest.get("published_authority_queue_path") != "bridge/hold.ndjson":
        raise ValueError("PUBLISHED_AUTHORITY_QUEUE_PATH_MISMATCH")
    if manifest.get("responsible_person_payload_emitted") is not False:
        raise ValueError("RESPONSIBLE_PERSON_BOUNDARY_VIOLATION")

    authority_bytes = authority_path.read_bytes()
    input_sha = _sha256_bytes(authority_bytes)
    expected_sha = str(manifest.get("authority_required_payload_sha256") or "")
    if (
        input_sha != expected_sha
        or input_sha != str(manifest.get("hold_payload_sha256") or "")
    ):
        raise ValueError("AUTHORITY_INPUT_SHA_MISMATCH")

    rows = list(_iter_authority(authority_path))
    if len(rows) != int(manifest.get("authority_required_seller_count", -1)):
        raise ValueError("AUTHORITY_INPUT_COUNT_MISMATCH")

    buckets: dict[str, list[dict[str, object]]] = {
        "branch_parent_required.ndjson": [],
        "ambiguous_type_required.ndjson": [],
        "unsupported_type_required.ndjson": [],
    }
    for row in rows:
        buckets[REASON_TO_FILE[str(row["reason"])]].append(row)

    expected_counts = {
        "branch_parent_required.ndjson": int(
            manifest.get("branch_parent_authority_required_count", -1)
        ),
        "ambiguous_type_required.ndjson": int(
            manifest.get("ambiguous_type_authority_required_count", -1)
        ),
        "unsupported_type_required.ndjson": int(
            manifest.get("unsupported_type_authority_required_count", -1)
        ),
    }
    for name, bucket in buckets.items():
        if len(bucket) != expected_counts[name]:
            raise ValueError(f"AUTHORITY_REASON_COUNT_MISMATCH:{name}")

    output_dir.mkdir(parents=True, exist_ok=True)
    outputs: dict[str, dict[str, object]] = {}
    for name in sorted(buckets):
        payload = b"".join(_line(row) for row in buckets[name])
        (output_dir / name).write_bytes(payload)
        outputs[name] = {
            "seller_count": len(buckets[name]),
            "payload_sha256": _sha256_bytes(payload),
        }

    source_manifest_bytes = bridge_manifest_path.read_bytes()
    result = {
        "schema_version": 1,
        "gate": "P4.20.3-D-stronger-authority-cohort",
        "validation_subset": False,
        "input_authority_queue_path": "bridge/hold.ndjson",
        "input_authority_seller_count": len(rows),
        "input_authority_payload_sha256": input_sha,
        "input_bridge_manifest_sha256": _sha256_bytes(source_manifest_bytes),
        "authority_surface": [
            "seller_identifier",
            "candidate_entity_types",
            "reason",
        ],
        "branch_without_parent_policy": "HOLD_UNTIL_AUTHORITATIVE_PARENT",
        "responsible_person_payload_emitted": False,
        "mobile_per_invoice_network_lookup": False,
        "final_mobile_registry": False,
        "outputs": outputs,
    }
    (output_dir / "stronger_authority_manifest.json").write_text(
        json.dumps(
            result,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n",
        encoding="utf-8",
    )
    print("P4_20_3_STRONGER_AUTHORITY_COHORT=PASS")
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return result


def self_test() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        rows = [
            {
                "candidate_entity_types": ["branch"],
                "reason": "branch_parent_identity_required",
                "seller_identifier": "11111111",
            },
            {
                "candidate_entity_types": ["branch", "company"],
                "reason": "official_type_ambiguous_requires_authority",
                "seller_identifier": "22222222",
            },
            {
                "candidate_entity_types": [],
                "reason": "official_type_unsupported_requires_authority",
                "seller_identifier": "33333333",
            },
        ]
        authority = root / "hold.ndjson"
        authority.write_bytes(b"".join(_line(row) for row in rows))
        sha = _sha256_bytes(authority.read_bytes())
        bridge_manifest = root / "bridge_manifest.json"
        bridge_manifest.write_text(
            json.dumps(
                {
                    "validation_subset": False,
                    "hold_is_authority_required_queue": True,
                    "published_authority_queue_path": "bridge/hold.ndjson",
                    "responsible_person_payload_emitted": False,
                    "authority_required_payload_sha256": sha,
                    "hold_payload_sha256": sha,
                    "authority_required_seller_count": 3,
                    "branch_parent_authority_required_count": 1,
                    "ambiguous_type_authority_required_count": 1,
                    "unsupported_type_authority_required_count": 1,
                },
                sort_keys=True,
                separators=(",", ":"),
            )
            + "\n",
            encoding="utf-8",
        )
        result = build(authority, bridge_manifest, root / "out")
        assert result["input_authority_seller_count"] == 3
        assert (
            result["outputs"]["branch_parent_required.ndjson"]["seller_count"]
            == 1
        )
        assert (
            result["outputs"]["ambiguous_type_required.ndjson"]["seller_count"]
            == 1
        )
        assert (
            result["outputs"]["unsupported_type_required.ndjson"]["seller_count"]
            == 1
        )
        assert result["validation_subset"] is False
        assert result["responsible_person_payload_emitted"] is False
    print("P4_20_3_STRONGER_AUTHORITY_COHORT_SELFTEST=PASS")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("authority_queue", nargs="?", type=Path)
    parser.add_argument("bridge_manifest", nargs="?", type=Path)
    parser.add_argument("output_dir", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if not args.authority_queue or not args.bridge_manifest or not args.output_dir:
        parser.error(
            "authority_queue, bridge_manifest, and output_dir are required"
        )
    build(args.authority_queue, args.bridge_manifest, args.output_dir)


if __name__ == "__main__":
    main()
