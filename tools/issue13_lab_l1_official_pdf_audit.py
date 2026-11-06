#!/usr/bin/env python3
"""Fail-closed, read-only L1 PDF/text witness audit (not a prize verdict).

An Android API35 PdfRenderer page-text export is required as JSONL. JSONL is
not independently authenticated, so even complete coverage is never a
production NOT_WIN, C13/C17/C18, or Owner-device gate.
"""
import argparse
from collections import Counter
import hashlib
import json
import re
import sys
import unicodedata
from pathlib import Path

EXPECTED_BYTES = 135200798
EXPECTED_SHA256 = "f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571"
PERIOD = "115-07-08"
TIER = "cloud-500"
ENGINE = "android.graphics.pdf.PdfRenderer"
TOKEN = re.compile(r"(?<![A-Za-z0-9])[A-Z][ \t]*[A-Z](?:[ \t]*[0-9]){8}(?![A-Za-z0-9])")
CANONICAL = re.compile(r"^[A-Z]{2}[0-9]{8}$")


def pdf_identity(path, *, expected_bytes=EXPECTED_BYTES, expected_sha256=EXPECTED_SHA256):
    """Stream bytes; never load a 135 MB official PDF into Python memory."""
    digest = hashlib.sha256()
    size = 0
    prefix = b""
    tail = b""
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            if not prefix:
                prefix = chunk[:5]
            tail = (tail + chunk)[-2048:]
            size += len(chunk)
            if size > expected_bytes:
                raise ValueError("PDF_SIZE_EXCEEDED")
            digest.update(chunk)
    if size != expected_bytes or digest.hexdigest() != expected_sha256:
        raise ValueError("PDF_OFFICIAL_BYTES_SHA_MISMATCH")
    if prefix != b"%PDF-" or b"%%EOF" not in tail:
        raise ValueError("PDF_CONTAINER_MARKERS_MISSING")
    return {"bytes": size, "sha256": digest.hexdigest()}


def _tokens(text):
    raw = [re.sub(r"[ \t]", "", m.group()) for m in TOKEN.finditer(text)]
    normalized = unicodedata.normalize("NFKC", text)
    norm = [re.sub(r"[ \t]", "", m.group()) for m in TOKEN.finditer(normalized)]
    # Unicode compatibility folding may create apparent invoice numbers which
    # the actual renderer did not emit as canonical ASCII. Never infer a loss.
    if Counter(norm) != Counter(raw):
        raise ValueError("UNICODE_COMPATIBILITY_TOKEN_AMBIGUITY")
    if any(not CANONICAL.fullmatch(v) for v in raw):
        raise ValueError("NONCANONICAL_INVOICE_TOKEN")
    return raw


def audit_pages(records, *, pdf_sha256=EXPECTED_SHA256):
    """Validate complete page coverage and global order; no prize verdict."""
    count = None
    next_page = 1
    previous_max = None
    seen = set()
    token_total = 0
    for item in records:
        if not isinstance(item, dict) or set(item) != {
            "page", "page_count", "pdf_sha256", "engine", "period", "tier", "text"
        }:
            raise ValueError("PAGE_EVIDENCE_SCHEMA_MISMATCH")
        if item["pdf_sha256"] != pdf_sha256 or item["engine"] != ENGINE or \
                item["period"] != PERIOD or item["tier"] != TIER:
            raise ValueError("PAGE_EVIDENCE_SOURCE_OR_SCOPE_MISMATCH")
        page, pages, content = item["page"], item["page_count"], item["text"]
        if type(page) is not int or type(pages) is not int or \
                pages < 1 or pages > 100000 or page != next_page or \
                (count is not None and pages != count):
            raise ValueError("PAGE_COVERAGE_OR_ORDER_MISMATCH")
        if not isinstance(content, str) or len(content) > 2_000_000:
            raise ValueError("PAGE_TEXT_UNBOUNDED_OR_INVALID")
        count = pages
        tokens = _tokens(content)
        if not tokens:
            raise ValueError("PAGE_WITHOUT_CANONICAL_TOKENS")
        if len(tokens) != len(set(tokens)) or any(v in seen for v in tokens):
            raise ValueError("DUPLICATE_INVOICE_TOKEN")
        low, high = min(tokens), max(tokens)
        if previous_max is not None and low <= previous_max:
            raise ValueError("GLOBAL_PAGE_SORT_ORDER_UNPROVEN")
        seen.update(tokens)
        token_total += len(tokens)
        previous_max = high
        next_page += 1
    if count is None or next_page != count + 1:
        raise ValueError("INCOMPLETE_PAGE_COVERAGE")
    return {"pages": count, "canonical_tokens": token_total,
            "unique_tokens": len(seen), "page_coverage": "COMPLETE",
            "page_order": "MONOTONIC", "unicode_ambiguity": "NONE_DETECTED",
            "extraction_completeness": "UNATTESTED",
            "period_and_tier_publication_provenance": "UNATTESTED",
            "global_not_win_authority": "HOLD",
            "production_integration": "HOLD", "owner_device": "HOLD"}


def _unique_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("DUPLICATE_PAGE_EVIDENCE_FIELD")
        result[key] = value
    return result


def read_jsonl(path):
    with Path(path).open("r", encoding="utf-8") as source:
        while True:
            line = source.readline(2_100_001)
            if not line:
                break
            if len(line) > 2_100_000:
                raise ValueError("PAGE_EVIDENCE_LINE_UNBOUNDED")
            yield json.loads(line, object_pairs_hook=_unique_keys)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--official-pdf", required=True)
    parser.add_argument("--pages-jsonl", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    report = {"gate": "L1_OFFICIAL_PDF_EVIDENCE_HOLD", "official_pdf": "HOLD",
              "page_evidence": "HOLD", "global_not_win_authority": "HOLD",
              "production_integration": "HOLD", "owner_device": "HOLD"}
    try:
        report["source"] = pdf_identity(args.official_pdf)
        report["official_pdf"] = "SOURCE_BYTES_PASS"
        report["pages"] = audit_pages(read_jsonl(args.pages_jsonl),
                                       pdf_sha256=report["source"]["sha256"])
        report["page_evidence"] = "STRUCTURAL_AUDIT_PASS_UNATTESTED_EXTRACTION"
    except (ValueError, OSError, UnicodeError, json.JSONDecodeError) as exc:
        report["hold_reason"] = str(exc)
    Path(args.output).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n",
                                 encoding="utf-8")
    print("LAB_L1_SOURCE=" + report["official_pdf"])
    print("LAB_L1_PAGE_EVIDENCE=" + report["page_evidence"])
    print("LAB_L1_GLOBAL_NOT_WIN=HOLD")
    return 0 if report["page_evidence"].startswith("STRUCTURAL_AUDIT_PASS") else 49


if __name__ == "__main__":
    sys.exit(main())
