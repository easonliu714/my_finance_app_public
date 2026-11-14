#!/usr/bin/env python3
"""B2.7 isolated real-DGPA-116 source audit. Never install into production."""
import csv
import datetime as dt
import hashlib
import io
import os
from pathlib import Path
import ssl
import sys
import urllib.error
import urllib.request

URL = "https://www.dgpa.gov.tw/FileConversion?filename=dgpa%2Ffiles%2F202607%2Ff538b1ff-ba60-4c63-9477-10db8e6612d1.csv&name=116%E5%B9%B4%E4%B8%AD%E8%8F%AF%E6%B0%91%E5%9C%8B%E6%94%BF%E5%BA%9C%E8%A1%8C%E6%94%BF%E6%A9%9F%E9%97%9C%E8%BE%A6%E5%85%AC%E6%97%A5%E6%9B%86%E8%A1%A8_utf8bom.csv&nfix="
MAX_BYTES = 256 * 1024
HEADER = ("西元日期", "星期", "是否放假", "備註")
WEEKDAYS = "日一二三四五六"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise RuntimeError(f"Unapproved HTTP redirect status={code} target={newurl}")


def validate(raw):
    if not raw or len(raw) > MAX_BYTES:
        raise ValueError(f"size out of bounds: {len(raw)}")
    decoded = raw.decode("utf-8-sig", errors="strict")
    rows = list(csv.reader(io.StringIO(decoded, newline=""), strict=True))
    if not rows or tuple(x.strip() for x in rows[0]) != HEADER:
        raise ValueError(f"DGPA header mismatch: {rows[0] if rows else 'EMPTY'}")
    if len(rows) != 366:
        raise ValueError(f"2027 must have exactly 365 days: got {len(rows)-1}")
    start = dt.date(2027, 1, 1)
    holidays = 0
    for i, row in enumerate(rows[1:]):
        day = start + dt.timedelta(days=i)
        expected_weekday = WEEKDAYS[(day.weekday() + 1) % 7]
        if len(row) != 4:
            raise ValueError(f"row {i+2} column count {len(row)}")
        if row[0].strip() != day.strftime("%Y%m%d"):
            raise ValueError(f"row {i+2} date mismatch: {row[0]!r}")
        if row[1].strip() != expected_weekday:
            raise ValueError(f"row {i+2} weekday mismatch: {row[1]!r}")
        if row[2].strip() not in ("0", "2"):
            raise ValueError(f"row {i+2} holiday flag invalid: {row[2]!r}")
        if len(row[3]) > 200:
            raise ValueError(f"row {i+2} note too long")
        holidays += row[2].strip() == "2"
    return holidays


def assert_negative(label, raw):
    try:
        validate(raw)
    except (UnicodeError, ValueError, csv.Error):
        print(f"PASS B2_NEGATIVE_{label}")
        return
    raise AssertionError(f"B2 negative {label} was accepted")


def main():
    if not URL.startswith("https://www.dgpa.gov.tw/FileConversion?"):
        raise ValueError("Source URL must be exact official DGPA HTTPS FileConversion")
    opener = urllib.request.build_opener(
        urllib.request.HTTPSHandler(context=ssl.create_default_context()),
        NoRedirect(),
    )
    req = urllib.request.Request(
        URL, headers={"User-Agent": "my-finance-app-b2-source-lab/1.0",
                      "Accept": "text/csv,application/octet-stream"},
    )
    print("B2_OFFICIAL_SOURCE_ATTEMPT=DGPA_116", flush=True)
    with opener.open(req, timeout=35) as response:
        final = response.geturl()
        if final != URL or response.status != 200:
            raise ValueError(f"Source origin/status changed: {final}, {response.status}")
        declared = response.headers.get("Content-Length")
        if declared and int(declared) > MAX_BYTES:
            raise ValueError(f"Official Content-Length exceeds cap: {declared}")
        raw = response.read(MAX_BYTES + 1)
        content_type = response.headers.get("Content-Type", "unknown")
    digest = hashlib.sha256(raw).hexdigest()
    print(f"B2_SOURCE_HTTP=200 BYTES={len(raw)} TYPE={content_type}", flush=True)
    print(f"B2_SOURCE_SHA256={digest}", flush=True)
    holidays = validate(raw)
    assert_negative("UTF8", raw + b"\xff")
    assert_negative("TRUNCATED", raw[:max(1, len(raw)//2)])
    text = raw.decode("utf-8-sig")
    assert_negative("DUPLICATE_DATE", text.replace("20270102", "20270101", 1).encode("utf-8"))
    output = Path(os.environ["B2_CSV_OUT"])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(raw)
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as env:
        env.write(f"B2_OFFICIAL_CSV_SHA256={digest}\n")
    print(f"B2_REAL_SOURCE_EXECUTED=PASS ROWS=365 HOLIDAYS={holidays} SHA256={digest}", flush=True)
    print("B2_AUTHORITY_SCOPE=RAW_SOURCE_AND_SCHEMA_ONLY_NOT_SIGNED_NOT_OWNER_UAT", flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"B2_REAL_SOURCE_EXECUTED=FAIL FIRST_FAILURE={type(exc).__name__}: {exc}", file=sys.stderr, flush=True)
        raise SystemExit(49)
