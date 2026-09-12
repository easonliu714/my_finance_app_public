#!/usr/bin/env python3
"""Plan a bounded P4.20.3 stronger-authority delta without network access.

The current authority queue is compared with a prior authority index. Only NEW /
CHANGED / EXPIRED sellers are emitted into the queryable delta. Same-fingerprint,
unexpired terminal authority is reused. Same-fingerprint sellers that were
previously attempted but still lack terminal authority are held, not re-queried,
unless a later governed authority-path change makes them CHANGED or a separate
explicit retry/revalidation policy authorizes them.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import tempfile
from pathlib import Path

CURRENT_KEYS = {"seller_identifier", "candidate_entity_types", "reason"}
PRIOR_KEYS = {
    "seller_identifier",
    "cohort_fingerprint",
    "authority_status",
    "expires_at",
}
TERMINAL_STATUSES = {"TERMINAL", "RESOLVED"}
CATEGORIES = (
    "REUSE_TERMINAL",
    "NEW",
    "CHANGED",
    "MISSING_AUTHORITY",
    "EXPIRED",
)
# Cost-governance invariant: an unchanged seller that already went through the
# authority path but remains nonterminal must not be queried again merely because
# a downstream/checkpoint head changed. Retry/revalidation is a separate governed
# surface. This keeps same-generation MISSING_AUTHORITY fail-closed.
QUERYABLE = {"NEW", "CHANGED", "EXPIRED"}


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


def _load_current(path: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    previous = ""
    seen: set[str] = set()
    for line_no, raw in enumerate(
        path.read_text(encoding="utf-8-sig").splitlines(), 1
    ):
        if not raw.strip():
            continue
        row = json.loads(raw)
        if not isinstance(row, dict) or set(row) != CURRENT_KEYS:
            raise ValueError(f"CURRENT_SURFACE_MISMATCH:{line_no}")
        seller = _seller(row.get("seller_identifier"))
        if not seller:
            raise ValueError(f"CURRENT_INVALID_SELLER:{line_no}")
        if seller in seen:
            raise ValueError(f"CURRENT_DUPLICATE_SELLER:{seller}")
        if previous and seller < previous:
            raise ValueError(f"CURRENT_NOT_SORTED:{line_no}")
        candidates = row.get("candidate_entity_types")
        if (
            not isinstance(candidates, list)
            or candidates != sorted(set(str(v) for v in candidates))
        ):
            raise ValueError(f"CURRENT_CANDIDATE_TYPES_NOT_CANONICAL:{seller}")
        previous = seller
        seen.add(seller)
        rows.append(row)
    return rows


def _load_prior(path: Path) -> dict[str, dict[str, object]]:
    result: dict[str, dict[str, object]] = {}
    if not path.exists():
        return result
    for line_no, raw in enumerate(
        path.read_text(encoding="utf-8-sig").splitlines(), 1
    ):
        if not raw.strip():
            continue
        row = json.loads(raw)
        if not isinstance(row, dict) or set(row) != PRIOR_KEYS:
            raise ValueError(f"PRIOR_SURFACE_MISMATCH:{line_no}")
        seller = _seller(row.get("seller_identifier"))
        if not seller:
            raise ValueError(f"PRIOR_INVALID_SELLER:{line_no}")
        if seller in result:
            raise ValueError(f"PRIOR_DUPLICATE_SELLER:{seller}")
        fp = str(row.get("cohort_fingerprint") or "")
        if len(fp) != 64 or any(c not in "0123456789abcdef" for c in fp):
            raise ValueError(f"PRIOR_INVALID_FINGERPRINT:{seller}")
        _parse_time(str(row.get("expires_at") or ""))
        result[seller] = row
    return result


def classify(
    current: dict[str, object],
    prior: dict[str, object] | None,
    as_of: dt.datetime,
) -> str:
    if prior is None:
        return "NEW"
    current_fp = _fingerprint(current)
    if str(prior["cohort_fingerprint"]) != current_fp:
        return "CHANGED"
    if str(prior["authority_status"]) not in TERMINAL_STATUSES:
        return "MISSING_AUTHORITY"
    if _parse_time(str(prior["expires_at"])) <= as_of:
        return "EXPIRED"
    return "REUSE_TERMINAL"


def build(
    current_path: Path,
    prior_path: Path,
    output_dir: Path,
    as_of_text: str,
) -> dict[str, object]:
    as_of = _parse_time(as_of_text)
    current = _load_current(current_path)
    prior = _load_prior(prior_path)

    buckets: dict[str, list[dict[str, object]]] = {
        name: [] for name in CATEGORIES
    }
    for row in current:
        seller = str(row["seller_identifier"])
        category = classify(row, prior.get(seller), as_of)
        out = {
            "seller_identifier": seller,
            "candidate_entity_types": row["candidate_entity_types"],
            "reason": row["reason"],
            "cohort_fingerprint": _fingerprint(row),
            "delta_class": category,
        }
        buckets[category].append(out)

    output_dir.mkdir(parents=True, exist_ok=True)
    outputs: dict[str, dict[str, object]] = {}
    query_payload = b""
    for category in CATEGORIES:
        payload = b"".join(_line(r) for r in buckets[category])
        name = category.lower() + ".ndjson"
        (output_dir / name).write_bytes(payload)
        outputs[name] = {
            "seller_count": len(buckets[category]),
            "payload_sha256": hashlib.sha256(payload).hexdigest(),
        }
        if category in QUERYABLE:
            query_payload += payload

    (output_dir / "query_delta.ndjson").write_bytes(query_payload)
    query_count = sum(len(buckets[name]) for name in QUERYABLE)
    manifest = {
        "schema_version": 2,
        "gate": "P4.20.3-D-delta-authority-resolution-plan",
        "validation_subset": False,
        "as_of": as_of.isoformat().replace("+00:00", "Z"),
        "current_seller_count": len(current),
        "prior_authority_count": len(prior),
        "classification_counts": {
            name: len(buckets[name]) for name in CATEGORIES
        },
        "queryable_classes": sorted(QUERYABLE),
        "nonqueryable_unchanged_missing_authority": True,
        "missing_authority_retry_policy": "SEPARATE_EXPLICIT_GOVERNED_SURFACE_ONLY",
        "query_delta_seller_count": query_count,
        "query_delta_payload_sha256": hashlib.sha256(query_payload).hexdigest(),
        "reuse_terminal_seller_count": len(buckets["REUSE_TERMINAL"]),
        "responsible_person_payload_emitted": False,
        "mobile_per_invoice_network_lookup": False,
        "full_revalidation_policy": "SEPARATE_LOW_FREQUENCY_ONLY",
        "outputs": outputs,
    }
    (output_dir / "delta_authority_manifest.json").write_text(
        json.dumps(
            manifest,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n",
        encoding="utf-8",
    )
    print("P4_20_3_DELTA_AUTHORITY_RESOLUTION_PLAN=PASS")
    print(json.dumps(manifest, ensure_ascii=False, sort_keys=True))
    return manifest


def self_test() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        rows = [
            {
                "candidate_entity_types": ["company"],
                "reason": "type",
                "seller_identifier": "11111111",
            },
            {
                "candidate_entity_types": ["business", "company"],
                "reason": "type",
                "seller_identifier": "22222222",
            },
            {
                "candidate_entity_types": ["branch"],
                "reason": "parent",
                "seller_identifier": "33333333",
            },
            {
                "candidate_entity_types": ["company"],
                "reason": "type",
                "seller_identifier": "44444444",
            },
            {
                "candidate_entity_types": ["business"],
                "reason": "type",
                "seller_identifier": "55555555",
            },
        ]
        current = root / "current.ndjson"
        current.write_bytes(b"".join(_line(r) for r in rows))
        prior_rows = [
            {
                "seller_identifier": "11111111",
                "cohort_fingerprint": _fingerprint(rows[0]),
                "authority_status": "TERMINAL",
                "expires_at": "2026-10-01T00:00:00Z",
            },
            {
                "seller_identifier": "22222222",
                "cohort_fingerprint": "0" * 64,
                "authority_status": "TERMINAL",
                "expires_at": "2026-10-01T00:00:00Z",
            },
            {
                "seller_identifier": "33333333",
                "cohort_fingerprint": _fingerprint(rows[2]),
                "authority_status": "PENDING",
                "expires_at": "2026-10-01T00:00:00Z",
            },
            {
                "seller_identifier": "44444444",
                "cohort_fingerprint": _fingerprint(rows[3]),
                "authority_status": "RESOLVED",
                "expires_at": "2026-09-01T00:00:00Z",
            },
        ]
        prior = root / "prior.ndjson"
        prior.write_bytes(b"".join(_line(r) for r in prior_rows))
        result = build(
            current,
            prior,
            root / "out",
            "2026-09-08T00:00:00Z",
        )
        assert result["classification_counts"] == {
            "REUSE_TERMINAL": 1,
            "NEW": 1,
            "CHANGED": 1,
            "MISSING_AUTHORITY": 1,
            "EXPIRED": 1,
        }, result
        # MISSING_AUTHORITY is intentionally held: same fingerprint + same
        # generation must not become an automatic paid retry.
        assert result["query_delta_seller_count"] == 3
        assert result["reuse_terminal_seller_count"] == 1
        assert result["queryable_classes"] == ["CHANGED", "EXPIRED", "NEW"]
        assert result["nonqueryable_unchanged_missing_authority"] is True
        assert result["validation_subset"] is False
        assert result["responsible_person_payload_emitted"] is False
        print("P4_20_3_DELTA_AUTHORITY_RESOLUTION_PLAN_SELFTEST=PASS")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("current_authority_queue", nargs="?", type=Path)
    parser.add_argument("prior_authority_index", nargs="?", type=Path)
    parser.add_argument("output_dir", nargs="?", type=Path)
    parser.add_argument("--as-of")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if not all(
        (
            args.current_authority_queue,
            args.prior_authority_index,
            args.output_dir,
            args.as_of,
        )
    ):
        parser.error(
            "current_authority_queue, prior_authority_index, output_dir, "
            "and --as-of are required"
        )
    build(
        args.current_authority_queue,
        args.prior_authority_index,
        args.output_dir,
        args.as_of,
    )


if __name__ == "__main__":
    main()
