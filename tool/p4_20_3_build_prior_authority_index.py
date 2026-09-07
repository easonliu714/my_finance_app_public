#!/usr/bin/env python3
"""Build a seller-level prior authority LKG index without network access.

The index is derived from a frozen producer materialization. Each seller in the
producer stronger-authority queue keeps the canonical queue fingerprint used by
the delta planner. A seller is TERMINAL only when that same seller is present in
the frozen enriched entity payload; otherwise it is MISSING_AUTHORITY and must
remain nonqueryable unless a later governed surface authorizes retry.
"""
from __future__ import annotations

import argparse
import datetime as dt
import gzip
import hashlib
import json
import tempfile
from pathlib import Path

AUTHORITY_KEYS = {"seller_identifier", "candidate_entity_types", "reason"}
ENTITY_REQUIRED_KEYS = {"seller_identifier", "entity_type"}


def _seller(value: object) -> str:
    digits = "".join(ch for ch in str(value or "") if ch.isdigit())
    return digits if len(digits) == 8 else ""


def _canonical_bytes(row: dict[str, object]) -> bytes:
    return json.dumps(
        row, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def _fingerprint(row: dict[str, object]) -> str:
    return hashlib.sha256(_canonical_bytes(row)).hexdigest()


def _line(row: dict[str, object]) -> bytes:
    return _canonical_bytes(row) + b"\n"


def _parse_time(value: str) -> dt.datetime:
    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("TIMESTAMP_MUST_BE_OFFSET_AWARE")
    return parsed.astimezone(dt.timezone.utc)


def _load_authority_queue(path: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    previous = ""
    seen: set[str] = set()
    for line_no, raw in enumerate(
        path.read_text(encoding="utf-8-sig").splitlines(), 1
    ):
        if not raw.strip():
            continue
        row = json.loads(raw)
        if not isinstance(row, dict) or set(row) != AUTHORITY_KEYS:
            raise ValueError(f"AUTHORITY_SURFACE_MISMATCH:{line_no}")
        seller = _seller(row.get("seller_identifier"))
        if not seller:
            raise ValueError(f"AUTHORITY_INVALID_SELLER:{line_no}")
        if seller in seen:
            raise ValueError(f"AUTHORITY_DUPLICATE_SELLER:{seller}")
        if previous and seller < previous:
            raise ValueError(f"AUTHORITY_NOT_SORTED:{line_no}")
        candidates = row.get("candidate_entity_types")
        if (
            not isinstance(candidates, list)
            or candidates != sorted(set(str(v) for v in candidates))
        ):
            raise ValueError(f"AUTHORITY_CANDIDATE_TYPES_NOT_CANONICAL:{seller}")
        previous = seller
        seen.add(seller)
        rows.append(row)
    return rows


def _load_terminal_sellers(path: Path) -> set[str]:
    terminal: set[str] = set()
    previous = ""
    with gzip.open(path, "rt", encoding="utf-8-sig") as stream:
        for line_no, raw in enumerate(stream, 1):
            if not raw.strip():
                continue
            row = json.loads(raw)
            if not isinstance(row, dict) or not ENTITY_REQUIRED_KEYS.issubset(row):
                raise ValueError(f"ENTITY_SURFACE_MISMATCH:{line_no}")
            seller = _seller(row.get("seller_identifier"))
            if not seller:
                raise ValueError(f"ENTITY_INVALID_SELLER:{line_no}")
            if seller in terminal:
                raise ValueError(f"ENTITY_DUPLICATE_SELLER:{seller}")
            if previous and seller < previous:
                raise ValueError(f"ENTITY_NOT_SORTED:{line_no}")
            entity_type = str(row.get("entity_type") or "")
            if entity_type not in {"company", "business", "branch"}:
                raise ValueError(f"ENTITY_TYPE_INVALID:{seller}:{entity_type}")
            previous = seller
            terminal.add(seller)
    return terminal


def build(
    authority_queue: Path,
    enriched_entities_gzip: Path,
    output_dir: Path,
    observed_at_text: str,
    terminal_expires_at_text: str | None,
) -> dict[str, object]:
    observed_at = _parse_time(observed_at_text)
    terminal_expires_at = (
        _parse_time(terminal_expires_at_text) if terminal_expires_at_text else None
    )
    authority_rows = _load_authority_queue(authority_queue)
    terminal_sellers = _load_terminal_sellers(enriched_entities_gzip)
    queue_sellers = {str(row["seller_identifier"]) for row in authority_rows}
    overlap = queue_sellers & terminal_sellers
    if overlap and terminal_expires_at is None:
        raise ValueError("TERMINAL_EXPIRY_POLICY_REQUIRED")
    if terminal_expires_at is not None and terminal_expires_at <= observed_at:
        raise ValueError("TERMINAL_EXPIRY_MUST_FOLLOW_OBSERVED_AT")

    rows: list[dict[str, object]] = []
    terminal_count = 0
    missing_count = 0
    for row in authority_rows:
        seller = str(row["seller_identifier"])
        is_terminal = seller in terminal_sellers
        if is_terminal:
            terminal_count += 1
            expires_at = terminal_expires_at
            status = "TERMINAL"
        else:
            missing_count += 1
            # The delta planner checks nonterminal status before expiry, so this
            # timestamp is an observation boundary rather than retry authority.
            expires_at = observed_at
            status = "MISSING_AUTHORITY"
        assert expires_at is not None
        rows.append(
            {
                "seller_identifier": seller,
                "cohort_fingerprint": _fingerprint(row),
                "authority_status": status,
                "expires_at": expires_at.isoformat().replace("+00:00", "Z"),
            }
        )

    output_dir.mkdir(parents=True, exist_ok=True)
    payload = b"".join(_line(row) for row in rows)
    index_path = output_dir / "prior_authority_index.ndjson"
    index_path.write_bytes(payload)
    manifest = {
        "schema_version": 1,
        "gate": "P4.20.3-D-prior-terminal-authority-index",
        "validation_subset": False,
        "observed_at": observed_at.isoformat().replace("+00:00", "Z"),
        "authority_queue_seller_count": len(authority_rows),
        "terminal_entity_seller_count": len(terminal_sellers),
        "terminal_overlap_seller_count": terminal_count,
        "missing_authority_seller_count": missing_count,
        "terminal_expiry_policy_supplied": terminal_expires_at is not None,
        "prior_authority_index_sha256": hashlib.sha256(payload).hexdigest(),
        "responsible_person_payload_emitted": False,
        "mobile_per_invoice_network_lookup": False,
        "unchanged_missing_authority_queryable": False,
    }
    (output_dir / "prior_authority_index_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        + "\n",
        encoding="utf-8",
    )
    print("P4_20_3_PRIOR_AUTHORITY_INDEX=PASS")
    print(json.dumps(manifest, ensure_ascii=False, sort_keys=True))
    return manifest


def self_test() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        authority_rows = [
            {
                "candidate_entity_types": ["company"],
                "reason": "official_type_ambiguous_requires_authority",
                "seller_identifier": "11111111",
            },
            {
                "candidate_entity_types": ["branch"],
                "reason": "branch_parent_identity_required",
                "seller_identifier": "22222222",
            },
        ]
        authority = root / "hold.ndjson"
        authority.write_bytes(b"".join(_line(row) for row in authority_rows))
        entities = root / "entities.ndjson.gz"
        with gzip.open(entities, "wt", encoding="utf-8") as stream:
            stream.write(
                json.dumps(
                    {
                        "record_type": "entity",
                        "seller_identifier": "11111111",
                        "entity_type": "company",
                    },
                    sort_keys=True,
                    separators=(",", ":"),
                )
                + "\n"
            )
        try:
            build(
                authority,
                entities,
                root / "missing_policy",
                "2026-09-06T21:13:30Z",
                None,
            )
        except ValueError as exc:
            assert str(exc) == "TERMINAL_EXPIRY_POLICY_REQUIRED", exc
        else:
            raise AssertionError("TERMINAL_EXPIRY_POLICY_REQUIRED_NOT_ENFORCED")
        result = build(
            authority,
            entities,
            root / "out",
            "2026-09-06T21:13:30Z",
            "2026-10-06T21:13:30Z",
        )
        assert result["authority_queue_seller_count"] == 2
        assert result["terminal_overlap_seller_count"] == 1
        assert result["missing_authority_seller_count"] == 1
        assert result["unchanged_missing_authority_queryable"] is False
        rows = [
            json.loads(line)
            for line in (root / "out" / "prior_authority_index.ndjson")
            .read_text(encoding="utf-8")
            .splitlines()
            if line.strip()
        ]
        assert rows[0]["authority_status"] == "TERMINAL"
        assert rows[1]["authority_status"] == "MISSING_AUTHORITY"
    print("P4_20_3_PRIOR_AUTHORITY_INDEX_SELFTEST=PASS")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("authority_queue", nargs="?", type=Path)
    parser.add_argument("enriched_entities_gzip", nargs="?", type=Path)
    parser.add_argument("output_dir", nargs="?", type=Path)
    parser.add_argument("--observed-at")
    parser.add_argument("--terminal-expires-at")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if not all(
        (
            args.authority_queue,
            args.enriched_entities_gzip,
            args.output_dir,
            args.observed_at,
        )
    ):
        parser.error(
            "authority_queue, enriched_entities_gzip, output_dir and --observed-at "
            "are required"
        )
    build(
        args.authority_queue,
        args.enriched_entities_gzip,
        args.output_dir,
        args.observed_at,
        args.terminal_expires_at,
    )


if __name__ == "__main__":
    main()
