#!/usr/bin/env python3
"""P4.20.3 Gate D controlled-build GCIS registration-type acquisition.

Queries the official MOEA/GCIS endpoint "統編查是否為公司、分公司及商業" only
for a precomputed FIA residual seller cohort. This is build-time evidence
acquisition, never a handset/per-invoice lookup path.

The output intentionally preserves the official TYPE values without guessing a
company/business/branch mapping. Downstream code must establish that mapping
from official evidence before producing mobile canonical entities.

Large residual cohorts may be split into deterministic shards. Sharding is
performed only after exact seller normalization, deduplication and sorting, so
the same seller filter + shard-count always yields the same membership.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Callable

API_ID = "673F0FC0-B3A7-429F-9041-E9866836B66D"
BASE_URL = f"https://data.gcis.nat.gov.tw/od/data/api/{API_ID}"
SOURCE_DATASET = "GCIS:統編查是否為公司、分公司及商業"
LICENSE = "政府資料開放授權條款-第1版"
OUTPUT_KEYS = {
    "seller_identifier",
    "official_types",
    "official_exists_values",
    "official_year_values",
    "source_dataset",
}


def _clean(value: object) -> str:
    return str(value or "").strip()


def _seller(value: object) -> str:
    digits = "".join(ch for ch in _clean(value) if ch.isdigit())
    return digits if len(digits) == 8 else ""


def _line(record: dict[str, object]) -> bytes:
    return (json.dumps(record, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def _load_sellers(path: Path) -> list[str]:
    sellers: set[str] = set()
    with path.open("r", encoding="utf-8-sig") as stream:
        for line_number, raw in enumerate(stream, 1):
            line = raw.strip()
            if not line:
                continue
            value: object = line
            if line.startswith("{"):
                try:
                    decoded = json.loads(line)
                except json.JSONDecodeError as exc:
                    raise ValueError(f"INVALID_FILTER_JSON_LINE:{line_number}") from exc
                if not isinstance(decoded, dict):
                    raise ValueError(f"INVALID_FILTER_RECORD:{line_number}")
                value = decoded.get("seller_identifier", "")
            seller = _seller(value)
            if not seller:
                raise ValueError(f"INVALID_FILTER_SELLER_IDENTIFIER:{line_number}")
            sellers.add(seller)
    if not sellers:
        raise ValueError("EMPTY_SELLER_FILTER")
    return sorted(sellers)


def _select_shard(sellers: list[str], shard_index: int, shard_count: int) -> list[str]:
    if shard_count <= 0:
        raise ValueError("SHARD_COUNT_MUST_BE_POSITIVE")
    if shard_index < 0 or shard_index >= shard_count:
        raise ValueError("SHARD_INDEX_OUT_OF_RANGE")
    selected = sellers[shard_index::shard_count]
    if not selected:
        raise ValueError("EMPTY_SELECTED_SHARD")
    return selected


def _request_url(seller: str) -> str:
    query = urllib.parse.urlencode({
        "$format": "json",
        "$filter": f"No eq {seller}",
        "$skip": "0",
        "$top": "50",
    })
    return f"{BASE_URL}?{query}"


def _parse_rows(payload: object, seller: str) -> dict[str, object]:
    if not isinstance(payload, list):
        raise ValueError("GCIS_RESPONSE_NOT_LIST")
    types: set[str] = set()
    exists_values: set[str] = set()
    years: set[str] = set()
    for index, row in enumerate(payload):
        if not isinstance(row, dict):
            raise ValueError(f"GCIS_RESPONSE_ROW_NOT_OBJECT:{index}")
        # Official dataset documentation defines Year / exist / TYPE. We only
        # project these classification fields and never serialize other payload.
        if "TYPE" not in row or "exist" not in row:
            raise ValueError(f"GCIS_RESPONSE_REQUIRED_FIELDS_MISSING:{index}")
        type_value = _clean(row.get("TYPE"))
        exists_value = _clean(row.get("exist"))
        year_value = _clean(row.get("Year"))
        if type_value:
            types.add(type_value)
        if exists_value:
            exists_values.add(exists_value)
        if year_value:
            years.add(year_value)
    record = {
        "seller_identifier": seller,
        "official_types": sorted(types),
        "official_exists_values": sorted(exists_values),
        "official_year_values": sorted(years),
        "source_dataset": SOURCE_DATASET,
    }
    if set(record) != OUTPUT_KEYS:
        raise AssertionError("INTERNAL_OUTPUT_SURFACE_MISMATCH")
    return record


def _default_fetch(url: str, timeout_seconds: float) -> tuple[bytes, dict[str, str]]:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "my-finance-app-P4.20.3-controlled-build/1"},
    )
    with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
        body = response.read()
        headers = {key.lower(): value for key, value in response.headers.items()}
    return body, headers


def acquire(
    sellers: list[str],
    output_dir: Path,
    *,
    qps: float,
    timeout_seconds: float,
    retries: int,
    source_filter_unique_count: int | None = None,
    shard_index: int = 0,
    shard_count: int = 1,
    fetcher: Callable[[str, float], tuple[bytes, dict[str, str]]] = _default_fetch,
) -> dict[str, object]:
    if qps <= 0:
        raise ValueError("QPS_MUST_BE_POSITIVE")
    if retries < 0:
        raise ValueError("RETRIES_MUST_BE_NONNEGATIVE")
    if shard_count <= 0:
        raise ValueError("SHARD_COUNT_MUST_BE_POSITIVE")
    if shard_index < 0 or shard_index >= shard_count:
        raise ValueError("SHARD_INDEX_OUT_OF_RANGE")
    output_dir.mkdir(parents=True, exist_ok=True)
    evidence_path = output_dir / "registration_type_evidence.ndjson"
    failure_path = output_dir / "acquisition_failures.ndjson"
    interval = 1.0 / qps
    digest = hashlib.sha256()
    success_count = 0
    failure_count = 0
    total_response_bytes = 0
    last_modified_values: set[str] = set()

    with evidence_path.open("wb") as evidence, failure_path.open("wb") as failures:
        for index, seller in enumerate(sellers):
            if index:
                time.sleep(interval)
            url = _request_url(seller)
            record: dict[str, object] | None = None
            last_reason = ""
            last_error = ""
            for attempt in range(retries + 1):
                try:
                    body, headers = fetcher(url, timeout_seconds)
                except (urllib.error.URLError, TimeoutError, OSError) as exc:
                    last_reason = "transport_failure"
                    last_error = f"{type(exc).__name__}:{exc}"
                else:
                    total_response_bytes += len(body)
                    if headers.get("last-modified"):
                        last_modified_values.add(headers["last-modified"])
                    try:
                        payload = json.loads(body.decode("utf-8-sig"))
                        record = _parse_rows(payload, seller)
                    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
                        # HTTP success does not guarantee a valid GCIS JSON contract.
                        # Empty/HTML/transient upstream bodies must receive the same
                        # bounded retry treatment as transport failures; otherwise a
                        # single transient 200 response permanently breaks shard
                        # completeness despite the official query being replayable.
                        last_reason = "response_contract_failure"
                        last_error = str(exc)
                    else:
                        break
                if attempt < retries:
                    time.sleep(min(2 ** attempt, 8))

            if record is None:
                failures.write(_line({
                    "seller_identifier": seller,
                    "reason": last_reason or "unknown_failure",
                    "detail": last_error[:240],
                }))
                failure_count += 1
                continue

            encoded = _line(record)
            evidence.write(encoded)
            digest.update(encoded)
            success_count += 1

    if success_count + failure_count != len(sellers):
        raise AssertionError("ACQUISITION_PARTITION_MISMATCH")
    full_filter_count = source_filter_unique_count if source_filter_unique_count is not None else len(sellers)
    manifest = {
        "schema_version": 2,
        "gate": "P4.20.3-D",
        "endpoint_api_id": API_ID,
        "endpoint_url": BASE_URL,
        "source_dataset": SOURCE_DATASET,
        "license": LICENSE,
        "seller_filter_unique_count": full_filter_count,
        "selected_shard_seller_count": len(sellers),
        "shard_index": shard_index,
        "shard_count": shard_count,
        "shard_selection": "sorted_unique_sellers[index::shard_count]",
        "success_count": success_count,
        "failure_count": failure_count,
        "qps_limit": qps,
        "timeout_seconds": timeout_seconds,
        "retry_count": retries,
        "total_response_bytes": total_response_bytes,
        "http_last_modified_values": sorted(last_modified_values),
        "evidence_payload_sha256": digest.hexdigest(),
        "responsible_person_payload_emitted": False,
        "merchant_name_inference_used": False,
        "mobile_per_invoice_network_lookup": False,
        "official_type_mapping_applied": False,
        "final_mobile_registry": False,
    }
    (output_dir / "acquisition_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print("P4_20_3_GCIS_REGISTRATION_TYPE_ACQUISITION=PASS")
    print(json.dumps(manifest, ensure_ascii=False, sort_keys=True))
    return manifest


def self_test() -> None:
    with __import__("tempfile").TemporaryDirectory() as temp:
        root = Path(temp)
        sellers_file = root / "residual.ndjson"
        sellers_file.write_text(
            '{"seller_identifier":"20828393"}\n'
            '{"seller_identifier":"22555003"}\n'
            '{"seller_identifier":"22853565"}\n'
            '{"seller_identifier":"31655572"}\n',
            encoding="utf-8",
        )
        all_sellers = _load_sellers(sellers_file)
        shard0 = _select_shard(all_sellers, 0, 2)
        shard1 = _select_shard(all_sellers, 1, 2)
        assert shard0 == ["20828393", "22853565"]
        assert shard1 == ["22555003", "31655572"]
        assert sorted(shard0 + shard1) == all_sellers
        fixtures = {
            "20828393": [{"Year": "2026", "exist": "Y", "TYPE": "COMPANY", "ignored_sensitive_field": "never serialized"}],
            "22853565": [{"Year": "2026", "exist": "Y", "TYPE": "COMPANY", "representative": "never serialized"}],
        }

        def fake_fetch(url: str, timeout_seconds: float) -> tuple[bytes, dict[str, str]]:
            assert timeout_seconds == 1.0
            seller = "20828393" if "20828393" in url else "22853565"
            return json.dumps(fixtures[seller], ensure_ascii=False).encode("utf-8"), {"last-modified": "fixture"}

        manifest = acquire(
            shard0,
            root / "out",
            qps=1000.0,
            timeout_seconds=1.0,
            retries=0,
            source_filter_unique_count=len(all_sellers),
            shard_index=0,
            shard_count=2,
            fetcher=fake_fetch,
        )
        rows = [json.loads(line) for line in (root / "out" / "registration_type_evidence.ndjson").read_text(encoding="utf-8").splitlines()]
        assert len(rows) == 2
        assert all(set(row) == OUTPUT_KEYS for row in rows)
        assert "ignored_sensitive_field" not in rows[0]
        assert "representative" not in rows[1]
        assert manifest["seller_filter_unique_count"] == 4
        assert manifest["selected_shard_seller_count"] == 2
        assert manifest["shard_index"] == 0
        assert manifest["shard_count"] == 2
        assert manifest["success_count"] == 2
        assert manifest["failure_count"] == 0
        assert manifest["official_type_mapping_applied"] is False
        assert manifest["mobile_per_invoice_network_lookup"] is False

        # Regression: a transient HTTP-success/invalid-body response must be
        # retried rather than becoming an immediate terminal shard failure.
        transient_calls = 0

        def transient_contract_fetch(url: str, timeout_seconds: float) -> tuple[bytes, dict[str, str]]:
            nonlocal transient_calls
            transient_calls += 1
            if transient_calls == 1:
                return b"", {}
            return json.dumps(fixtures["20828393"]).encode("utf-8"), {}

        transient_manifest = acquire(
            ["20828393"],
            root / "transient-contract",
            qps=1000.0,
            timeout_seconds=1.0,
            retries=1,
            fetcher=transient_contract_fetch,
        )
        assert transient_calls == 2
        assert transient_manifest["success_count"] == 1
        assert transient_manifest["failure_count"] == 0
        assert (root / "transient-contract" / "acquisition_failures.ndjson").read_text(encoding="utf-8") == ""

        # Regression: a permanently invalid contract remains an explicit
        # terminal disposition after the bounded retry budget is exhausted.
        permanent_calls = 0

        def permanent_contract_fetch(url: str, timeout_seconds: float) -> tuple[bytes, dict[str, str]]:
            nonlocal permanent_calls
            permanent_calls += 1
            return b"", {}

        permanent_manifest = acquire(
            ["20828393"],
            root / "permanent-contract",
            qps=1000.0,
            timeout_seconds=1.0,
            retries=2,
            fetcher=permanent_contract_fetch,
        )
        permanent_failure = json.loads(
            (root / "permanent-contract" / "acquisition_failures.ndjson").read_text(encoding="utf-8").strip()
        )
        assert permanent_calls == 3
        assert permanent_manifest["success_count"] == 0
        assert permanent_manifest["failure_count"] == 1
        assert permanent_failure["reason"] == "response_contract_failure"

        try:
            _select_shard(all_sellers, 2, 2)
        except ValueError as exc:
            assert str(exc) == "SHARD_INDEX_OUT_OF_RANGE"
        else:
            raise AssertionError("SHARD_INDEX_OUT_OF_RANGE_NOT_REJECTED")
    print("P4_20_3_GCIS_REGISTRATION_TYPE_ACQUISITION_SELFTEST=PASS")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("seller_filter", nargs="?", type=Path)
    parser.add_argument("output_dir", nargs="?", type=Path)
    parser.add_argument("--qps", type=float, default=2.0)
    parser.add_argument("--timeout-seconds", type=float, default=15.0)
    parser.add_argument("--retries", type=int, default=3)
    parser.add_argument("--shard-index", type=int, default=0)
    parser.add_argument("--shard-count", type=int, default=1)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.seller_filter is None or args.output_dir is None:
        parser.error("seller_filter and output_dir are required unless --self-test is used")
    all_sellers = _load_sellers(args.seller_filter)
    selected_sellers = _select_shard(all_sellers, args.shard_index, args.shard_count)
    acquire(
        selected_sellers,
        args.output_dir,
        qps=args.qps,
        timeout_seconds=args.timeout_seconds,
        retries=args.retries,
        source_filter_unique_count=len(all_sellers),
        shard_index=args.shard_index,
        shard_count=args.shard_count,
    )


if __name__ == "__main__":
    main()
