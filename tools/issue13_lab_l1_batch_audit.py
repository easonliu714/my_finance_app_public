"""Lab-only L1 partial JSONL batch contract. Never emits NOT_WIN."""
from issue13_lab_l1_official_pdf_audit import (
    EXPECTED_SHA256, ENGINE, PERIOD, TIER, _tokens,
)

FIELDS = {"page", "page_count", "pdf_sha256", "engine", "period", "tier", "text"}


def audit_batch(rows, *, first):
    if type(first) is not int or first < 1 or first > 100000:
        raise ValueError("L1_BATCH_START_INVALID")
    rows = list(rows)
    if not 1 <= len(rows) <= 4:
        raise ValueError("L1_BATCH_PAGE_BUDGET")
    page_count = None
    previous = None
    seen = set()
    for offset, row in enumerate(rows):
        if not isinstance(row, dict) or set(row) != FIELDS:
            raise ValueError("L1_BATCH_SCHEMA")
        if (row["pdf_sha256"] != EXPECTED_SHA256 or row["engine"] != ENGINE
                or row["period"] != PERIOD or row["tier"] != TIER):
            raise ValueError("L1_BATCH_SOURCE_SCOPE")
        if (type(row["page"]) is not int or row["page"] != first + offset
                or type(row["page_count"]) is not int
                or row["page_count"] < first + offset
                or row["page_count"] > 100000
                or (page_count is not None and page_count != row["page_count"])):
            raise ValueError("L1_BATCH_RANGE_ORDER")
        page_count = row["page_count"]
        content = row["text"]
        if not isinstance(content, str) or len(content) > 250000:
            raise ValueError("L1_BATCH_TEXT_BUDGET")
        tokens = _tokens(content)
        if not tokens:
            raise ValueError("L1_BATCH_NO_TOKENS")
        if len(tokens) != len(set(tokens)) or any(x in seen for x in tokens):
            raise ValueError("L1_BATCH_DUPLICATE")
        if tokens != sorted(tokens):
            raise ValueError("L1_BATCH_INTRA_PAGE_SORT_UNPROVEN")
        if previous is not None and min(tokens) <= previous:
            raise ValueError("L1_BATCH_SORT_UNPROVEN")
        previous = max(tokens)
        seen.update(tokens)
    return {"status": "PARTIAL_STRUCTURAL_ONLY", "start_page": first,
            "end_page": first + len(rows) - 1, "page_count": page_count,
            "tokens": len(seen), "global_not_win": "HOLD",
            "full_page_coverage": "HOLD"}
