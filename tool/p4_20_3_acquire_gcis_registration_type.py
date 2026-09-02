#!/usr/bin/env python3
"""P4.20.3 Gate D controlled-build GCIS registration-type acquisition.

Queries the official MOEA/GCIS endpoint "統編查是否為公司、分公司及商業" only
for a precomputed FIA residual seller cohort.  This is build-time evidence
acquisition, never a handset/per-invoice lookup path.

The output intentionally preserves the official TYPE values without guessing a
company/business/branch mapping.  Downstream code must establish that mapping
from official evidence before producing mobile canonical entities.
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
        # Official dataset documentation defines Year / exist / TYPE.  We only
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
    fetcher: Callable[[str, float], tuple[bytes, dict[str, str]]] = _default_fetch,
) -> dict[str, object]:
    if qps <= 0:
        raise ValueError("QPS_MUST_BE_POSITIVE")
    if retries < 0:
        raise ValueError("RETRIES_MUST_BE_NONNEGATIVE")
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
            body: bytes | None = None
            headers: dict[str, str] = {}
            last_error = ""
            for attempt in range(retries + 1):
                try:
                    body, headers = fetcher(url, timeout_seconds)
                    break
                except (urllib.error.URLError, TimeoutError, OSError) as exc:
                    last_error = f"{type(exc).__name__}:{exc}"
                    if attempt < retries:
                        time.sleep(min(2 ** attempt, 8))
            if body is None:
                failures.write(_line({"seller_identifier": seller, "reason": "transport_failure", "detail": last_error[:240]}))
                failure_count += 1
                continue
            total_response_bytes += len(body)
            if headers.get("last-modified"):
                last_modified_values.add(headers["last-modified"])
            try:
                payload = json.loads(body.decode("utf-8-sig"))
                record = _parse_rows(payload, seller)
            except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
                failures.write(_line({"seller_identifier": seller, "reason": "response_contract_failure", "detail": str(exc)[:240]}))
                failure_count += 1
                continue
            encoded = _line(record)
            evidence.write(encoded)
            digest.update(encoded)
            success_count += 1

    if success_count + failure_count != len(sellers):
        raise AssertionError("ACQUISITION_PARTITION_MISMATCH")
    manifest = {
        "schema_version": 1,
        "gate": "P4.20.3-D",
        "endpoint_api_id": API_ID,
        "endpoint_url": BASE_URL,
        "source_dataset": SOURCE_DATASET,
        "license": LICENSE,
        "seller_filter_unique_count": len(sellers),
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
            '{"seller_identifier":"31655572"}\n',
            encoding="utf-8",
        )
        sellers = _load_sellers(sellers_file)
        fixtures = {
            "20828393": [{"Year": "2026", "exist": "Y", "TYPE": "COMPANY", "ignored_sensitive_field": "never serialized"}],
            "31655572": [{"Year": "2026", "exist": "Y", "TYPE": "BRANCH", "representative": "never serialized"}],
        }

        def fake_fetch(url: str, timeout_seconds: float) -> tuple[bytes, dict[str, str]]:
            assert timeout_seconds == 1.0
            seller = "20828393" if "20828393" in url else "31655572"
            return json.dumps(fixtures[seller], ensure_ascii=False).encode("utf-8"), {"last-modified": "fixture"}

        manifest = acquire(sellers, root / "out", qps=1000.0, timeout_seconds=1.0, retries=0, fetcher=fake_fetch)
        rows = [json.loads(line) for line in (root / "out" / "registration_type_evidence.ndjson").read_text(encoding="utf-8").splitlines()]
        assert len(rows) == 2
        assert all(set(row) == OUTPUT_KEYS for row in rows)
        assert "ignored_sensitive_field" not in rows[0]
        assert "representative" not in rows[1]
        assert manifest["success_count"] == 2
        assert manifest["failure_count"] == 0
        assert manifest["official_type_mapping_applied"] is False
        assert manifest["mobile_per_invoice_network_lookup"] is False
    print("P4_20_3_GCIS_REGISTRATION_TYPE_ACQUISITION_SELFTEST=PASS")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("seller_filter", nargs="?", type=Path)
    parser.add_argument("output_dir", nargs="?", type=Path)
    parser.add_argument("--qps", type=float, default=2.0)
    parser.add_argument("--timeout-seconds", type=float, default=15.0)
    parser.add_argument("--retries", type=int, default=3)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.seller_filter is None or args.output_dir is None:
        parser.error("seller_filter and output_dir are required unless --self-test is used")
    sellers = _load_sellers(args.seller_filter)
    acquire(
        sellers,
        args.output_dir,
        qps=args.qps,
        timeout_seconds=args.timeout_seconds,
        retries=args.retries,
    )


if __name__ == "__main__":
    main()
