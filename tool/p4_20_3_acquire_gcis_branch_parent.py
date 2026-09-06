#!/usr/bin/env python3
"""Acquire authoritative GCIS parent identity for a bounded branch-only cohort.

This is controlled build-time evidence acquisition. It consumes only the SHA-bound
``branch_parent_identity_required`` cohort produced by P4.20.3 stronger-authority
partitioning and queries the official GCIS branch-by-branch endpoint. The mobile
projection never contains manager, responsible-person, address, or other unrelated
fields and normal invoice recognition never calls this endpoint.
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

API_ID = "23632BB3-5DB7-4423-9643-1D4AC140D479"
BASE_URL = f"https://data.gcis.nat.gov.tw/od/data/api/{API_ID}"
SOURCE_DATASET = "GCIS:分公司統編查分公司資料"
LICENSE = "政府資料開放授權條款-第1版"
INPUT_KEYS = {"seller_identifier", "candidate_entity_types", "reason"}
OUTPUT_KEYS = {"seller_identifier", "parent_seller_identifier", "source_dataset"}


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


def _request_url(seller: str) -> str:
    query = urllib.parse.urlencode({
        "$format": "json",
        "$filter": f"Branch_Office_Business_Accounting_NO eq {seller}",
        "$skip": "0",
        "$top": "50",
    })
    return f"{BASE_URL}?{query}"


def _parse_rows(payload: object, seller: str) -> dict[str, object] | None:
    if not isinstance(payload, list):
        raise ValueError("GCIS_BRANCH_RESPONSE_NOT_LIST")
    parents: set[str] = set()
    matched_rows = 0
    for index, row in enumerate(payload):
        if not isinstance(row, dict):
            raise ValueError(f"GCIS_BRANCH_RESPONSE_ROW_NOT_OBJECT:{index}")
        if "Branch_Office_Business_Accounting_NO" not in row or "Business_Accounting_NO" not in row:
            raise ValueError(f"GCIS_BRANCH_REQUIRED_FIELDS_MISSING:{index}")
        branch = _seller(row.get("Branch_Office_Business_Accounting_NO"))
        if branch != seller:
            raise ValueError(f"GCIS_BRANCH_IDENTIFIER_MISMATCH:{index}:{branch}")
        parent = _seller(row.get("Business_Accounting_NO"))
        if not parent:
            raise ValueError(f"GCIS_BRANCH_PARENT_IDENTIFIER_INVALID:{index}")
        if parent == seller:
            raise ValueError(f"GCIS_BRANCH_PARENT_SELF_REFERENCE:{seller}")
        parents.add(parent)
        matched_rows += 1
    if matched_rows == 0:
        return None
    if len(parents) != 1:
        raise ValueError(f"GCIS_BRANCH_PARENT_AMBIGUOUS:{seller}:{sorted(parents)}")
    record = {
        "seller_identifier": seller,
        "parent_seller_identifier": next(iter(parents)),
        "source_dataset": SOURCE_DATASET,
    }
    if set(record) != OUTPUT_KEYS:
        raise AssertionError("INTERNAL_BRANCH_PARENT_OUTPUT_SURFACE_MISMATCH")
    return record


def _default_fetch(url: str, timeout_seconds: float) -> tuple[bytes, dict[str, str]]:
    request = urllib.request.Request(url, headers={"User-Agent": "my-finance-app-P4.20.3-controlled-build/1"})
    with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
        return response.read(), {key.lower(): value for key, value in response.headers.items()}


def acquire(
    sellers: list[str],
    output_dir: Path,
    *,
    input_payload_sha256: str,
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
        last_error = ""
        for attempt in range(retries + 1):
            try:
                body, headers = fetcher(_request_url(seller), timeout_seconds)
                total_response_bytes += len(body)
                if headers.get("last-modified"):
                    last_modified_values.add(headers["last-modified"])
                parsed = _parse_rows(json.loads(body.decode("utf-8-sig")), seller)
                if parsed is None:
                    unresolved[seller] = "official_branch_record_not_found"
                else:
                    records[seller] = parsed
                last_error = ""
                break
            except (urllib.error.URLError, TimeoutError, OSError, http.client.HTTPException, UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
                last_error = f"{type(exc).__name__}:{exc}"[:240]
                if attempt < retries:
                    time.sleep(min(2 ** attempt, 8))
        if last_error:
            unresolved[seller] = f"acquisition_or_contract_failure:{last_error}"

    evidence_payload = b"".join(_line(records[s]) for s in sellers if s in records)
    unresolved_payload = b"".join(
        _line({"seller_identifier": s, "reason": unresolved[s]}) for s in sellers if s in unresolved
    )
    evidence_path.write_bytes(evidence_payload)
    unresolved_path.write_bytes(unresolved_payload)
    if len(records) + len(unresolved) != len(sellers):
        raise AssertionError("BRANCH_PARENT_PARTITION_MISMATCH")

    manifest = {
        "schema_version": 1,
        "gate": "P4.20.3-D-branch-parent-authority",
        "endpoint_api_id": API_ID,
        "endpoint_url": BASE_URL,
        "source_dataset": SOURCE_DATASET,
        "license": LICENSE,
        "input_branch_cohort_seller_count": len(sellers),
        "input_branch_cohort_payload_sha256": input_payload_sha256,
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
    (output_dir / "branch_parent_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print("P4_20_3_GCIS_BRANCH_PARENT_ACQUISITION=PASS")
    print(json.dumps(manifest, ensure_ascii=False, sort_keys=True))
    return manifest


def self_test() -> None:
    import tempfile
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        cohort = root / "branch_parent_required.ndjson"
        rows = [
            {"candidate_entity_types": ["branch"], "reason": "branch_parent_identity_required", "seller_identifier": "22956458"},
            {"candidate_entity_types": ["branch"], "reason": "branch_parent_identity_required", "seller_identifier": "31655572"},
        ]
        cohort.write_bytes(b"".join(_line(row) for row in rows))
        sellers, cohort_sha = _load_branch_cohort(cohort, _sha256_bytes(cohort.read_bytes()))
        fixtures = {
            "22956458": [{
                "Business_Accounting_NO": "20828393",
                "Branch_Office_Business_Accounting_NO": "22956458",
                "Branch_Office_Manager_Name": "must never serialize",
                "Branch_Office_Name": "must never serialize",
            }],
            "31655572": [],
        }
        def fixture_fetch(url: str, timeout_seconds: float) -> tuple[bytes, dict[str, str]]:
            seller = "22956458" if "22956458" in url else "31655572"
            return json.dumps(fixtures[seller], ensure_ascii=False).encode(), {"last-modified": "fixture"}
        manifest = acquire(sellers, root / "out", input_payload_sha256=cohort_sha,
                           qps=1000, timeout_seconds=1, retries=0, fetcher=fixture_fetch)
        assert manifest["resolved_parent_count"] == 1
        assert manifest["unresolved_parent_count"] == 1
        evidence = [json.loads(x) for x in (root/"out"/"branch_parent_evidence.ndjson").read_text().splitlines()]
        assert evidence == [{
            "parent_seller_identifier": "20828393",
            "seller_identifier": "22956458",
            "source_dataset": SOURCE_DATASET,
        }]
        assert all(set(row) == OUTPUT_KEYS for row in evidence)
        assert "Manager" not in json.dumps(evidence, ensure_ascii=False)
        try:
            _parse_rows([{"Business_Accounting_NO":"22956458", "Branch_Office_Business_Accounting_NO":"22956458"}], "22956458")
        except ValueError as exc:
            assert str(exc).startswith("GCIS_BRANCH_PARENT_SELF_REFERENCE:")
        else:
            raise AssertionError("SELF_PARENT_NOT_REJECTED")
        try:
            _parse_rows([
                {"Business_Accounting_NO":"20828393", "Branch_Office_Business_Accounting_NO":"22956458"},
                {"Business_Accounting_NO":"22853565", "Branch_Office_Business_Accounting_NO":"22956458"},
            ], "22956458")
        except ValueError as exc:
            assert str(exc).startswith("GCIS_BRANCH_PARENT_AMBIGUOUS:")
        else:
            raise AssertionError("AMBIGUOUS_PARENT_NOT_REJECTED")
    print("P4_20_3_GCIS_BRANCH_PARENT_SELFTEST=PASS")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("branch_cohort", nargs="?", type=Path)
    parser.add_argument("output_dir", nargs="?", type=Path)
    parser.add_argument("--expected-input-sha256")
    parser.add_argument("--qps", type=float, default=1.0)
    parser.add_argument("--timeout-seconds", type=float, default=20.0)
    parser.add_argument("--retries", type=int, default=2)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if not args.branch_cohort or not args.output_dir:
        parser.error("branch_cohort and output_dir are required")
    sellers, digest = _load_branch_cohort(args.branch_cohort, args.expected_input_sha256)
    acquire(sellers, args.output_dir, input_payload_sha256=digest,
            qps=args.qps, timeout_seconds=args.timeout_seconds, retries=args.retries)


if __name__ == "__main__":
    main()
