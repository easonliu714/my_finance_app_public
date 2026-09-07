#!/usr/bin/env python3
"""Regression contract for generation-driven P4.20.3 stronger-authority counts."""
from __future__ import annotations

import hashlib
import json
import tempfile
from pathlib import Path

from p4_20_3_build_stronger_authority_cohort import build


def _line(row: dict[str, object]) -> bytes:
    return (json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n").encode()


def _manifest(path: Path, rows: list[dict[str, object]]) -> Path:
    payload = b"".join(_line(row) for row in rows)
    path.write_bytes(payload)
    sha = hashlib.sha256(payload).hexdigest()
    counts = {
        "branch_parent_identity_required": 0,
        "official_type_ambiguous_requires_authority": 0,
        "official_type_unsupported_requires_authority": 0,
    }
    for row in rows:
        counts[str(row["reason"])] += 1
    manifest = path.with_name("bridge_manifest.json")
    manifest.write_text(
        json.dumps(
            {
                "validation_subset": False,
                "hold_is_authority_required_queue": True,
                "published_authority_queue_path": "bridge/hold.ndjson",
                "responsible_person_payload_emitted": False,
                "authority_required_payload_sha256": sha,
                "hold_payload_sha256": sha,
                "authority_required_seller_count": len(rows),
                "branch_parent_authority_required_count": counts[
                    "branch_parent_identity_required"
                ],
                "ambiguous_type_authority_required_count": counts[
                    "official_type_ambiguous_requires_authority"
                ],
                "unsupported_type_authority_required_count": counts[
                    "official_type_unsupported_requires_authority"
                ],
            },
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n",
        encoding="utf-8",
    )
    return manifest


def main() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        bridge = root / "bridge"
        bridge.mkdir()
        hold = bridge / "hold.ndjson"
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
                "candidate_entity_types": ["branch", "company"],
                "reason": "official_type_ambiguous_requires_authority",
                "seller_identifier": "33333333",
            },
            {
                "candidate_entity_types": [],
                "reason": "official_type_unsupported_requires_authority",
                "seller_identifier": "44444444",
            },
        ]
        manifest = _manifest(hold, rows)
        result = build(hold, manifest, root / "out")
        assert result["input_authority_seller_count"] == 4
        assert result["outputs"]["branch_parent_required.ndjson"]["seller_count"] == 1
        assert result["outputs"]["ambiguous_type_required.ndjson"]["seller_count"] == 2
        assert result["outputs"]["unsupported_type_required.ndjson"]["seller_count"] == 1
        print("P4_20_3_NON_HISTORICAL_GENERATION_COUNT=PASS")

        broken = json.loads(manifest.read_text(encoding="utf-8"))
        broken["authority_required_seller_count"] = 5
        manifest.write_text(
            json.dumps(broken, sort_keys=True, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )
        try:
            build(hold, manifest, root / "negative")
        except ValueError as exc:
            assert str(exc) == "AUTHORITY_INPUT_COUNT_MISMATCH", exc
        else:
            raise AssertionError("INCONSISTENT_MANIFEST_COUNT_UNEXPECTEDLY_ACCEPTED")
        print("P4_20_3_INCONSISTENT_MANIFEST_COUNT_FAIL_STOP=PASS")


if __name__ == "__main__":
    main()
