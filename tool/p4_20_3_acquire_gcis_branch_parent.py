#!/usr/bin/env python3
"""Verify authoritative GCIS parent identity for a bounded branch-only cohort.

Production contract:
- Stage A parent discovery is external and must arrive as an explicit SHA-bound,
  replayable candidate file from an approved official source.
- Stage B verifies each candidate against the formal, non-test GCIS
  company->branches API (API 28: 統編查分公司資料).
- The mobile projection contains only branch seller ID, parent seller ID, and
  source dataset. Manager/responsible-person/name/address fields are forbidden.
- Normal invoice recognition never calls this endpoint.

This tool intentionally does NOT use GCIS test reverse-lookup endpoints and does
NOT guess a parent when Stage A authority is absent.
"""
from __future__ import annotations

import argparse
import hashlib
import http.client
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Callable

FORMAL_API_ID = "FDB8D2C8-573D-4276-BFA4-8D3925ABE1CB"
FORMAL_BASE_URL = f"https://data.gcis.nat.gov.tw/od/data/api/{FORMAL_API_ID}"
FORMAL_SOURCE_DATASET = "GCIS:統編查分公司資料"
LICENSE = "政府資料開放授權條款-第1版"
INPUT_KEYS = {"seller_identifier", "candidate_entity_types", "reason"}
CANDIDATE_KEYS = {"seller_identifier", "parent_seller_identifier", "source_dataset"}
OUTPUT_KEYS = {"seller_identifier", "parent_seller_identifier", "source_dataset", "candidate_source_dataset"}


def _clean(value: object) -> str:
    return str(value or "").strip()


def _seller(value: object) -> str:
    digits = "".join(ch for ch in _clean(value) if ch.isdigit())
    return digits if len(digits) == 8 else ""


def _line(record: dict[str, object]) -> bytes:
    return (json.dumps(record, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _load_branch_cohort(path: Path, expected_sha256: str | None = None) -> tuple[list[str], str]:
    payload = path.read_bytes()
    digest = _sha256_bytes(payload)
    if expected_sha256 and digest != expected_sha256.lower():
        raise ValueError("BRANCH_COHORT_SHA_MISMATCH")
    sellers: list[str] = []
    previous = ""
    seen: set[str] = set()
    with path.open("r", encoding="utf-8-sig") as stream:
        for line_number, raw in enumerate(stream, 1):
            if not raw.strip():
                continue
            row = json.loads(raw)
            if not isinstance(row, dict) or set(row) != INPUT_KEYS:
                raise ValueError(f"BRANCH_COHORT_SURFACE_MISMATCH:{line_number}")
            seller = _seller(row.get("seller_identifier"))
            if not seller:
                raise ValueError(f"INVALID_BRANCH_SELLER_IDENTIFIER:{line_number}")
            if row.get("candidate_entity_types") != ["branch"]:
                raise ValueError(f"BRANCH_COHORT_TYPE_MISMATCH:{seller}")
            if row.get("reason") != "branch_parent_identity_required":
                raise ValueError(f"BRANCH_COHORT_REASON_MISMATCH:{seller}")
            if seller in seen:
                raise ValueError(f"DUPLICATE_BRANCH_SELLER_IDENTIFIER:{seller}")
            if previous and seller < previous:
                raise ValueError(f"BRANCH_COHORT_NOT_SORTED:{line_number}")
            previous = seller
            seen.add(seller)
            sellers.append(seller)
    if not sellers:
        raise ValueError("EMPTY_BRANCH_COHORT")
    return sellers, digest


def _load_parent_candidates(path: Path, sellers: list[str], expected_sha256: str | None = None) -> tuple[dict[str, dict[str, str]], str]:
    payload = path.read_bytes()
    digest = _sha256_bytes(payload)
    if expected_sha256 and digest != expected_sha256.lower():
        raise ValueError("PARENT_CANDIDATE_SHA_MISMATCH")
    allowed = set(sellers)
    rows: dict[str, dict[str, str]] = {}
    previous = ""
    with path.open("r", encoding="utf-8-sig") as stream:
        for line_number, raw in enumerate(stream, 1):
            if not raw.strip():
                continue
            row = json.loads(raw)
            if not isinstance(row, dict) or set(row) != CANDIDATE_KEYS:
                raise ValueError(f"PARENT_CANDIDATE_SURFACE_MISMATCH:{line_number}")
            seller = _seller(row.get("seller_identifier"))
            parent = _seller(row.get("parent_seller_identifier"))
            source_dataset = _clean(row.get("source_dataset"))
            if not seller or seller not in allowed:
                raise ValueError(f"PARENT_CANDIDATE_SELLER_OUT_OF_COHORT:{line_number}")
            if not parent:
                raise ValueError(f"PARENT_CANDIDATE_PARENT_INVALID:{seller}")
            if parent == seller:
                raise ValueError(f"PARENT_CANDIDATE_SELF_REFERENCE:{seller}")
            if not source_dataset:
                raise ValueError(f"PARENT_CANDIDATE_SOURCE_REQUIRED:{seller}")
            if seller in rows:
                raise ValueError(f"DUPLICATE_PARENT_CANDIDATE:{seller}")
            if previous and seller < previous:
                raise ValueError(f"PARENT_CANDIDATE_NOT_SORTED:{line_number}")
            previous = seller
            rows[seller] = {"seller_identifier": seller, "parent_seller_identifier": parent, "source_dataset": source_dataset}
    return rows, digest


def _request_url(parent: str) -> str:
    query = urllib.parse.urlencode({"$format": "json", "$filter": f"Business_Accounting_NO eq {parent}", "$skip": "0", "$top": "1000"})
    return f"{FORMAL_BASE_URL}?{query}"


def _parse_formal_rows(payload: object, seller: str, parent: str, candidate_source_dataset: str) -> dict[str, object] | None:
    if not isinstance(payload, list):
        raise ValueError("GCIS_FORMAL_BRANCH_RESPONSE_NOT_LIST")
    seen_exact = False
    for index, row in enumerate(payload):
        if not isinstance(row, dict):
            raise ValueError(f"GCIS_FORMAL_BRANCH_RESPONSE_ROW_NOT_OBJECT:{index}")
        if "Branch_Office_Business_Accounting_NO" not in row or "Business_Accounting_NO" not in row:
            raise ValueError(f"GCIS_FORMAL_BRANCH_REQUIRED_FIELDS_MISSING:{index}")
        row_parent = _seller(row.get("Business_Accounting_NO"))
        row_branch = _seller(row.get("Branch_Office_Business_Accounting_NO"))
        if row_parent != parent:
            raise ValueError(f"GCIS_FORMAL_PARENT_IDENTIFIER_MISMATCH:{index}:{row_parent}")
        if row_branch == seller:
            seen_exact = True
    if not seen_exact:
        return None
    record = {
        "seller_identifier": seller,
        "parent_seller_identifier": parent,
        "source_dataset": FORMAL_SOURCE_DATASET,
        "candidate_source_dataset": candidate_source_dataset,
    }
    if set(record) != OUTPUT_KEYS:
        raise AssertionError("INTERNAL_BRANCH_PARENT_OUTPUT_SURFACE_MISMATCH")
    return record


def _classify_payload_error(body: bytes, exc: Exception) -> str:
    preview = body[:160].decode("utf-8", errors="replace").strip().lower()
    if "非授權介接之ip" in preview or "unauthorized" in preview:
        return "upstream_ip_authorization_denied"
    return f"{type(exc).__name__}:{exc}"[:240]


def _default_fetch(url: str, timeout_seconds: float) -> tuple[bytes, dict[str, str]]:
    request = urllib.request.Request(url, headers={"User-Agent": "my-finance-app-P4.20.3-controlled-build/2"})
    with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
        return response.read(), {key.lower(): value for key, value in response.headers.items()}


def acquire(
    sellers: list[str],
    candidates: dict[str, dict[str, str]],
    output_dir: Path,
    *,
    input_payload_sha256: str,
    candidate_payload_sha256: str,
    qps: float,
    timeout_seconds: float,
    retries: int,
    fetcher: Callable[[str, float], tuple[bytes, dict[str, str]]] = _default_fetch,
) -> dict[str, object]:
    if qps <= 0:
        raise ValueError("QPS_MUST_BE_POSITIVE")
    if retries < 0:
        raise ValueError("RETRIES_MUST_BE_NONNEGATIVE")
    output_dir.mkdir(parents=True, exist_ok=True)
    evidence_path = output_dir / "branch_parent_evidence.ndjson"
    unresolved_path = output_dir / "branch_parent_unresolved.ndjson"
    records: dict[str, dict[str, object]] = {}
    unresolved: dict[str, str] = {}
    last_modified_values: set[str] = set()
    total_response_bytes = 0
    interval = 1.0 / qps

    for seller_index, seller in enumerate(sellers):
        if seller_index:
            time.sleep(interval)
        candidate = candidates.get(seller)
        if candidate is None:
            unresolved[seller] = "authoritative_parent_candidate_missing"
            continue
        parent = candidate["parent_seller_identifier"]
        last_error = ""
        for attempt in range(retries + 1):
            body = b""
            try:
                body, headers = fetcher(_request_url(parent), timeout_seconds)
                total_response_bytes += len(body)
                if headers.get("last-modified"):
                    last_modified_values.add(headers["last-modified"])
                try:
                    decoded = json.loads(body.decode("utf-8-sig"))
                except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                    raise ValueError(_classify_payload_error(body, exc)) from exc
                parsed = _parse_formal_rows(decoded, seller, parent, candidate["source_dataset"])
                if parsed is None:
                    unresolved[seller] = "formal_parent_membership_not_confirmed"
                else:
                    records[seller] = parsed
                last_error = ""
                break
            except (urllib.error.URLError, TimeoutError, OSError, http.client.HTTPException, ValueError) as exc:
                last_error = str(exc)[:240]
                if attempt < retries:
                    time.sleep(min(2**attempt, 8))
        if last_error:
            unresolved[seller] = f"verification_failure:{last_error}"

    evidence_payload = b"".join(_line(records[s]) for s in sellers if s in records)
    unresolved_payload = b"".join(_line({"seller_identifier": s, "reason": unresolved[s]}) for s in sellers if s in unresolved)
    evidence_path.write_bytes(evidence_payload)
    unresolved_path.write_bytes(unresolved_payload)
    if len(records) + len(unresolved) != len(sellers):
        raise AssertionError("BRANCH_PARENT_PARTITION_MISMATCH")

    manifest = {
        "schema_version": 2,
        "gate": "P4.20.3-D-branch-parent-authority",
        "formal_verification_api_id": FORMAL_API_ID,
        "formal_verification_url": FORMAL_BASE_URL,
        "formal_source_dataset": FORMAL_SOURCE_DATASET,
        "test_reverse_endpoint_used": False,
        "parent_candidate_discovery_required": True,
        "license": LICENSE,
        "input_branch_cohort_seller_count": len(sellers),
        "input_branch_cohort_payload_sha256": input_payload_sha256,
        "parent_candidate_count": len(candidates),
        "parent_candidate_payload_sha256": candidate_payload_sha256,
        "resolved_parent_count": len(records),
        "unresolved_parent_count": len(unresolved),
        "evidence_payload_sha256": _sha256_bytes(evidence_payload),
        "unresolved_payload_sha256": _sha256_bytes(unresolved_payload),
        "http_last_modified_values": sorted(last_modified_values),
        "total_response_bytes": total_response_bytes,
        "parent_child_identity_preserved": True,
        "branch_parent_guessing_used": False,
        "responsible_person_payload_emitted": False,
        "branch_manager_payload_emitted": False,
        "merchant_name_inference_used": False,
        "mobile_per_invoice_network_lookup": False,
        "validation_subset": False,
        "final_mobile_registry": False,
    }
    (output_dir / "branch_parent_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    print("P4_20_3_GCIS_BRANCH_PARENT_ACQUISITION=PASS")
    print(json.dumps(manifest, ensure_ascii=False, sort_keys=True))
    return manifest


def self_test() -> None:
    import tempfile
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        cohort = root / "branch_parent_required.ndjson"
        cohort_rows = [
            {"candidate_entity_types": ["branch"], "reason": "branch_parent_identity_required", "seller_identifier": "22956458"},
            {"candidate_entity_types": ["branch"], "reason": "branch_parent_identity_required", "seller_identifier": "31655572"},
        ]
        cohort.write_bytes(b"".join(_line(row) for row in cohort_rows))
        sellers, cohort_sha = _load_branch_cohort(cohort, _sha256_bytes(cohort.read_bytes()))
        candidate_path = root / "parent_candidates.ndjson"
        candidate_rows = [{"parent_seller_identifier": "20828393", "seller_identifier": "22956458", "source_dataset": "OFFICIAL_FIXTURE"}]
        candidate_path.write_bytes(b"".join(_line(row) for row in candidate_rows))
        candidates, candidate_sha = _load_parent_candidates(candidate_path, sellers, _sha256_bytes(candidate_path.read_bytes()))
        fixture_rows = [{"Business_Accounting_NO": "20828393", "Branch_Office_Business_Accounting_NO": "22956458", "Branch_Office_Manager_Name": "must never serialize", "Branch_Office_Name": "must never serialize"}]
        def fixture_fetch(url: str, timeout_seconds: float) -> tuple[bytes, dict[str, str]]:
            assert FORMAL_API_ID in url
            assert "20828393" in url
            return json.dumps(fixture_rows, ensure_ascii=False).encode(), {"last-modified": "fixture"}
        manifest = acquire(sellers, candidates, root / "out", input_payload_sha256=cohort_sha, candidate_payload_sha256=candidate_sha, qps=1000, timeout_seconds=1, retries=0, fetcher=fixture_fetch)
        assert manifest["resolved_parent_count"] == 1
        assert manifest["unresolved_parent_count"] == 1
        assert manifest["test_reverse_endpoint_used"] is False
        evidence = [json.loads(x) for x in (root / "out" / "branch_parent_evidence.ndjson").read_text().splitlines()]
        assert evidence == [{"candidate_source_dataset": "OFFICIAL_FIXTURE", "parent_seller_identifier": "20828393", "seller_identifier": "22956458", "source_dataset": FORMAL_SOURCE_DATASET}]
        assert all(set(row) == OUTPUT_KEYS for row in evidence)
        assert "Manager" not in json.dumps(evidence, ensure_ascii=False)
        bad_candidate = root / "bad_candidate.ndjson"
        bad_candidate.write_bytes(_line({"parent_seller_identifier": "22956458", "seller_identifier": "22956458", "source_dataset": "OFFICIAL_FIXTURE"}))
        try:
            _load_parent_candidates(bad_candidate, sellers)
        except ValueError as exc:
            assert str(exc).startswith("PARENT_CANDIDATE_SELF_REFERENCE:")
        else:
            raise AssertionError("SELF_PARENT_NOT_REJECTED")
        nonmember = _parse_formal_rows([{"Business_Accounting_NO": "20828393", "Branch_Office_Business_Accounting_NO": "12345678"}], "22956458", "20828393", "OFFICIAL_FIXTURE")
        assert nonmember is None
        assert _classify_payload_error("非授權介接之IP".encode(), ValueError("x")) == "upstream_ip_authorization_denied"
    print("P4_20_3_GCIS_BRANCH_PARENT_SELFTEST=PASS")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("branch_cohort", nargs="?", type=Path)
    parser.add_argument("parent_candidates", nargs="?", type=Path)
    parser.add_argument("output_dir", nargs="?", type=Path)
    parser.add_argument("--expected-input-sha256")
    parser.add_argument("--expected-candidate-sha256")
    parser.add_argument("--qps", type=float, default=1.0)
    parser.add_argument("--timeout-seconds", type=float, default=20.0)
    parser.add_argument("--retries", type=int, default=2)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if not args.branch_cohort or not args.parent_candidates or not args.output_dir:
        parser.error("branch_cohort, parent_candidates, and output_dir are required")
    sellers, digest = _load_branch_cohort(args.branch_cohort, args.expected_input_sha256)
    candidates, candidate_digest = _load_parent_candidates(args.parent_candidates, sellers, args.expected_candidate_sha256)
    acquire(sellers, candidates, args.output_dir, input_payload_sha256=digest, candidate_payload_sha256=candidate_digest, qps=args.qps, timeout_seconds=args.timeout_seconds, retries=args.retries)


if __name__ == "__main__":
    main()
