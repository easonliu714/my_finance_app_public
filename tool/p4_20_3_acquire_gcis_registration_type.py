#!/usr/bin/env python3
"""P4.20.3 Gate D controlled-build GCIS registration-type acquisition.

Queries the official MOEA/GCIS endpoint only for a precomputed FIA residual
seller cohort. This is build-time evidence acquisition and is never a handset
or per-invoice lookup path.

The mobile projection intentionally preserves only official classification
fields. Responsible-person and other unrelated source fields are never emitted.
Large cohorts are deterministically sharded after seller normalization/sort.

``official_types`` contains only TYPE values whose same source row has
``exist == Y``. TYPE/exist pairing is preserved before aggregation so a
response containing company=N, branch=Y, business=N cannot be misrepresented
as three affirmative classifications.
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

    affirmative_types: set[str] = set()
    exists_values: set[str] = set()
    years: set[str] = set()
    for index, row in enumerate(payload):
        if not isinstance(row, dict):
            raise ValueError(f"GCIS_RESPONSE_ROW_NOT_OBJECT:{index}")
        if "TYPE" not in row or "exist" not in row:
            raise ValueError(f"GCIS_RESPONSE_REQUIRED_FIELDS_MISSING:{index}")
        type_value = _clean(row.get("TYPE"))
        exists_value = _clean(row.get("exist")).upper()
        year_value = _clean(row.get("Year"))
        if exists_value not in {"Y", "N"}:
            raise ValueError(f"GCIS_RESPONSE_EXIST_VALUE_UNSUPPORTED:{index}:{exists_value}")
        if exists_value == "Y":
            if not type_value:
                raise ValueError(f"GCIS_RESPONSE_AFFIRMATIVE_TYPE_MISSING:{index}")
            affirmative_types.add(type_value)
        exists_values.add(exists_value)
        if year_value:
            years.add(year_value)
    record = {
        "seller_identifier": seller,
        "official_types": sorted(affirmative_types),
        "official_exists_values": sorted(exists_values),
        "official_year_values": sorted(years),
        "source_dataset": SOURCE_DATASET,
    }
    if set(record) != OUTPUT_KEYS:
        raise AssertionError("INTERNAL_OUTPUT_SURFACE_MISMATCH")
    return record


def _default_fetch(url: str, timeout_seconds: float) -> tuple[bytes, dict[str, str]]:
    request = urllib.request.Request(url, headers={"User-Agent": "my-finance-app-P4.20.3-controlled-build/1"})
    with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
        body = response.read()
        headers = {key.lower(): value for key, value in response.headers.items()}
    return body, headers


def _fetch_one(
    seller: str,
    *,
    timeout_seconds: float,
    retries: int,
    fetcher: Callable[[str, float], tuple[bytes, dict[str, str]]],
    on_body: Callable[[bytes, dict[str, str]], None],
) -> tuple[dict[str, object] | None, str, str]:
    url = _request_url(seller)
    last_reason = ""
    last_error = ""
    for attempt in range(retries + 1):
        try:
            body, headers = fetcher(url, timeout_seconds)
        except (urllib.error.URLError, TimeoutError, OSError, http.client.HTTPException) as exc:
            last_reason = "transport_failure"
            last_error = f"{type(exc).__name__}:{exc}"
        else:
            on_body(body, headers)
            try:
                payload = json.loads(body.decode("utf-8-sig"))
                return _parse_rows(payload, seller), "", ""
            except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
                last_reason = "response_contract_failure"
                last_error = str(exc)
        if attempt < retries:
            time.sleep(min(2 ** attempt, 8))
    return None, last_reason or "unknown_failure", last_error


def acquire(
    sellers: list[str],
    output_dir: Path,
    *,
    qps: float,
    timeout_seconds: float,
    retries: int,
    recovery_rounds: int = 2,
    recovery_delay_seconds: float = 30.0,
    source_filter_unique_count: int | None = None,
    shard_index: int = 0,
    shard_count: int = 1,
    fetcher: Callable[[str, float], tuple[bytes, dict[str, str]]] = _default_fetch,
) -> dict[str, object]:
    if qps <= 0:
        raise ValueError("QPS_MUST_BE_POSITIVE")
    if retries < 0 or recovery_rounds < 0:
        raise ValueError("RETRY_COUNTS_MUST_BE_NONNEGATIVE")
    if recovery_delay_seconds < 0:
        raise ValueError("RECOVERY_DELAY_MUST_BE_NONNEGATIVE")
    if shard_count <= 0:
        raise ValueError("SHARD_COUNT_MUST_BE_POSITIVE")
    if shard_index < 0 or shard_index >= shard_count:
        raise ValueError("SHARD_INDEX_OUT_OF_RANGE")

    output_dir.mkdir(parents=True, exist_ok=True)
    evidence_path = output_dir / "registration_type_evidence.ndjson"
    failure_path = output_dir / "acquisition_failures.ndjson"
    interval = 1.0 / qps
    total_response_bytes = 0
    last_modified_values: set[str] = set()
    records: dict[str, dict[str, object]] = {}
    failures: dict[str, tuple[str, str]] = {}
    recovery_attempted_count = 0
    recovery_recovered_count = 0

    def observe(body: bytes, headers: dict[str, str]) -> None:
        nonlocal total_response_bytes
        total_response_bytes += len(body)
        if headers.get("last-modified"):
            last_modified_values.add(headers["last-modified"])

    pending = list(sellers)
    for round_index in range(recovery_rounds + 1):
        if round_index > 0:
            if not pending:
                break
            recovery_attempted_count += len(pending)
            if recovery_delay_seconds:
                time.sleep(recovery_delay_seconds)
        next_pending: list[str] = []
        for index, seller in enumerate(pending):
            if index:
                time.sleep(interval)
            record, reason, detail = _fetch_one(
                seller,
                timeout_seconds=timeout_seconds,
                retries=retries,
                fetcher=fetcher,
                on_body=observe,
            )
            if record is None:
                failures[seller] = (reason, detail)
                next_pending.append(seller)
                continue
            if round_index > 0:
                recovery_recovered_count += 1
            records[seller] = record
            failures.pop(seller, None)
        pending = next_pending

    digest = hashlib.sha256()
    with evidence_path.open("wb") as evidence:
        for seller in sellers:
            record = records.get(seller)
            if record is None:
                continue
            encoded = _line(record)
            evidence.write(encoded)
            digest.update(encoded)
    with failure_path.open("wb") as failure_stream:
        for seller in sellers:
            failure = failures.get(seller)
            if failure is None:
                continue
            reason, detail = failure
            failure_stream.write(_line({
                "seller_identifier": seller,
                "reason": reason,
                "detail": detail[:240],
            }))

    success_count = len(records)
    failure_count = len(failures)
    if success_count + failure_count != len(sellers):
        raise AssertionError("ACQUISITION_PARTITION_MISMATCH")

    full_filter_count = source_filter_unique_count if source_filter_unique_count is not None else len(sellers)
    manifest = {
        "schema_version": 4,
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
        "recovery_round_count": recovery_rounds,
        "recovery_delay_seconds": recovery_delay_seconds,
        "recovery_attempted_count": recovery_attempted_count,
        "recovery_recovered_count": recovery_recovered_count,
        "total_response_bytes": total_response_bytes,
        "http_last_modified_values": sorted(last_modified_values),
        "evidence_payload_sha256": digest.hexdigest(),
        "official_type_exist_pairing_preserved": True,
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
            '{"seller_identifier":"31655572"}\n', encoding="utf-8")
        all_sellers = _load_sellers(sellers_file)
        shard0 = _select_shard(all_sellers, 0, 2)
        shard1 = _select_shard(all_sellers, 1, 2)
        assert shard0 == ["20828393", "22853565"]
        assert shard1 == ["22555003", "31655572"]
        fixtures = {
            "20828393": [{"Year":"2026","exist":"Y","TYPE":"COMPANY","representative":"never serialized"}],
            "22853565": [{"Year":"2026","exist":"Y","TYPE":"COMPANY","representative":"never serialized"}],
        }

        def ok_fetch(url: str, timeout_seconds: float) -> tuple[bytes, dict[str, str]]:
            seller = "20828393" if "20828393" in url else "22853565"
            return json.dumps(fixtures[seller]).encode(), {"last-modified":"fixture"}

        manifest = acquire(shard0, root/"ok", qps=1000, timeout_seconds=1, retries=0,
                           recovery_rounds=0, recovery_delay_seconds=0,
                           source_filter_unique_count=4, shard_index=0, shard_count=2, fetcher=ok_fetch)
        assert manifest["success_count"] == 2 and manifest["failure_count"] == 0
        assert manifest["official_type_exist_pairing_preserved"] is True
        rows = [json.loads(x) for x in (root/"ok"/"registration_type_evidence.ndjson").read_text().splitlines()]
        assert all(set(row) == OUTPUT_KEYS for row in rows)
        assert all("representative" not in row for row in rows)

        paired = _parse_rows([
            {"Year":"115","exist":"N","TYPE":"公司"},
            {"Year":"115","exist":"Y","TYPE":"分公司"},
            {"Year":"115","exist":"N","TYPE":"商業"},
        ], "31655572")
        assert paired["official_types"] == ["分公司"], paired
        assert paired["official_exists_values"] == ["N", "Y"], paired

        no_match = _parse_rows([
            {"Year":"115","exist":"N","TYPE":"公司"},
            {"Year":"115","exist":"N","TYPE":"分公司"},
            {"Year":"115","exist":"N","TYPE":"商業"},
        ], "22555003")
        assert no_match["official_types"] == [], no_match
        assert no_match["official_exists_values"] == ["N"], no_match

        try:
            _parse_rows([{"Year":"115","exist":"UNKNOWN","TYPE":"公司"}], "20828393")
        except ValueError as exc:
            assert str(exc).startswith("GCIS_RESPONSE_EXIST_VALUE_UNSUPPORTED:")
        else:
            raise AssertionError("GCIS_UNSUPPORTED_EXIST_VALUE_NOT_REJECTED")

        incomplete_calls = 0
        def incomplete_fetch(url: str, timeout_seconds: float) -> tuple[bytes, dict[str, str]]:
            nonlocal incomplete_calls
            incomplete_calls += 1
            if incomplete_calls == 1:
                raise http.client.IncompleteRead(b"partial", 10)
            return json.dumps(fixtures["20828393"]).encode(), {}
        m = acquire(["20828393"], root/"incomplete", qps=1000, timeout_seconds=1, retries=1,
                    recovery_rounds=0, recovery_delay_seconds=0, fetcher=incomplete_fetch)
        assert incomplete_calls == 2 and m["failure_count"] == 0

        recovery_calls = 0
        def recovery_fetch(url: str, timeout_seconds: float) -> tuple[bytes, dict[str, str]]:
            nonlocal recovery_calls
            recovery_calls += 1
            if recovery_calls <= 2:
                raise urllib.error.URLError("fixture 504 window")
            return json.dumps(fixtures["20828393"]).encode(), {}
        m = acquire(["20828393"], root/"recovery", qps=1000, timeout_seconds=1, retries=1,
                    recovery_rounds=1, recovery_delay_seconds=0, fetcher=recovery_fetch)
        assert recovery_calls == 3
        assert m["success_count"] == 1 and m["failure_count"] == 0
        assert m["recovery_attempted_count"] == 1 and m["recovery_recovered_count"] == 1
        assert (root/"recovery"/"acquisition_failures.ndjson").read_text() == ""

        permanent_calls = 0
        def permanent_fetch(url: str, timeout_seconds: float) -> tuple[bytes, dict[str, str]]:
            nonlocal permanent_calls
            permanent_calls += 1
            return b"", {}
        m = acquire(["20828393"], root/"permanent", qps=1000, timeout_seconds=1, retries=1,
                    recovery_rounds=1, recovery_delay_seconds=0, fetcher=permanent_fetch)
        assert permanent_calls == 4
        assert m["success_count"] == 0 and m["failure_count"] == 1
        failure = json.loads((root/"permanent"/"acquisition_failures.ndjson").read_text().strip())
        assert failure["reason"] == "response_contract_failure"

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
    parser.add_argument("--recovery-rounds", type=int, default=2)
    parser.add_argument("--recovery-delay-seconds", type=float, default=30.0)
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
        selected_sellers, args.output_dir,
        qps=args.qps, timeout_seconds=args.timeout_seconds, retries=args.retries,
        recovery_rounds=args.recovery_rounds, recovery_delay_seconds=args.recovery_delay_seconds,
        source_filter_unique_count=len(all_sellers), shard_index=args.shard_index, shard_count=args.shard_count,
    )


if __name__ == "__main__":
    main()
