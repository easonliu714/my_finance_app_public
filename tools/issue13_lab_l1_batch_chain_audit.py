#!/usr/bin/env python3
"""Stream bounded native L1 batches into a full-page structural audit.

Lab-only: even a complete, SHA-bound JSONL chain is NOT a prize verdict,
proof of renderer extraction completeness, or production authorization.
"""
import argparse
import json
import re
import sys
from pathlib import Path

from issue13_lab_l1_batch_audit import audit_batch
from issue13_lab_l1_official_pdf_audit import (
    _unique_keys, audit_pages, pdf_identity,
)

BATCH_NAME = re.compile(r"l1-pages-([1-9][0-9]*)-([0-9]{1,24})\.jsonl\Z")
MAX_BATCH_BYTES = 4_000_000
MAX_LINE_BYTES = 1_000_000


def _read_batch(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError("L1_CHAIN_UNTRUSTED_FILE")
    size = path.stat().st_size
    if size == 0 or size > MAX_BATCH_BYTES:
        raise ValueError("L1_CHAIN_BATCH_BYTES_BUDGET")
    rows = []
    with path.open("rb") as source:
        while True:
            line = source.readline(MAX_LINE_BYTES + 1)
            if not line:
                break
            if len(line) > MAX_LINE_BYTES or not line.endswith(b"\n"):
                raise ValueError("L1_CHAIN_JSONL_LINE_BUDGET")
            try:
                row = json.loads(line.decode("utf-8"), object_pairs_hook=_unique_keys)
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                raise ValueError("L1_CHAIN_JSONL_INVALID") from exc
            rows.append(row)
            if len(rows) > 4:
                raise ValueError("L1_CHAIN_PAGE_BUDGET")
    return rows


def audit_chain(directory):
    """No all-PDF/page-text buffering; each batch is at most four 1 MB rows."""
    root = Path(directory)
    if root.is_symlink() or not root.is_dir():
        raise ValueError("L1_CHAIN_DIRECTORY_INVALID")
    entries = []
    for path in root.iterdir():
        match = BATCH_NAME.fullmatch(path.name)
        if match is None or path.is_symlink() or not path.is_file():
            raise ValueError("L1_CHAIN_UNEXPECTED_ENTRY")
        entries.append((int(match.group(1)), path))
    if not entries or len(entries) > 25000:
        raise ValueError("L1_CHAIN_BATCH_COUNT_INVALID")
    entries.sort(key=lambda item: item[0])
    state = {"next_page": 1, "page_count": None, "batches": 0}

    def records():
        for start, path in entries:
            if start != state["next_page"]:
                raise ValueError("L1_CHAIN_GAP_OR_OVERLAP")
            rows = _read_batch(path)
            result = audit_batch(rows, first=start)
            count = result["page_count"]
            if state["page_count"] is not None and count != state["page_count"]:
                raise ValueError("L1_CHAIN_PAGE_COUNT_DRIFT")
            if len(rows) != min(4, count - start + 1):
                raise ValueError("L1_CHAIN_PARTIAL_BATCH")
            state["page_count"] = count
            state["next_page"] = start + len(rows)
            state["batches"] += 1
            yield from rows

    result = audit_pages(records())
    return {
        "status": "FULL_PAGE_STRUCTURAL_ONLY_UNATTESTED_EXTRACTION",
        "batches": state["batches"],
        **result,
        "global_not_win_authority": "HOLD",
        "production_integration": "HOLD",
        "owner_device": "HOLD",
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--official-pdf", required=True)
    parser.add_argument("--batch-dir", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    source_dir = Path(args.batch_dir).resolve()
    output = Path(args.output).resolve()
    if (output == source_dir or source_dir in output.parents
            or output == Path(args.official_pdf).resolve()):
        print("LAB_L1_OUTPUT_PATH_HOLD")
        return 49
    report = {"gate": "L1_OFFICIAL_PDF_EVIDENCE_HOLD",
              "official_pdf": "HOLD", "page_evidence": "HOLD",
              "global_not_win_authority": "HOLD"}
    try:
        report["source"] = pdf_identity(args.official_pdf)
        report["official_pdf"] = "SOURCE_BYTES_PASS"
        report["pages"] = audit_chain(args.batch_dir)
        report["page_evidence"] = "FULL_PAGE_STRUCTURAL_ONLY_UNATTESTED_EXTRACTION"
    except (ValueError, OSError, UnicodeError) as exc:
        report["hold_reason"] = str(exc)
    Path(args.output).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n",
                                 encoding="utf-8")
    print("LAB_L1_SOURCE=" + report["official_pdf"])
    print("LAB_L1_PAGE_EVIDENCE=" + report["page_evidence"])
    print("LAB_L1_GLOBAL_NOT_WIN=HOLD")
    return 0 if report["page_evidence"].startswith("FULL_PAGE_STRUCTURAL") else 49


if __name__ == "__main__":
    sys.exit(main())
