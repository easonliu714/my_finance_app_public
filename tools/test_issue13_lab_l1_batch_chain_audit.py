"""Synthetic-only L1 native-batch chain regressions; no official verdict."""
import json
import tempfile
import unittest
from pathlib import Path

from issue13_lab_l1_batch_chain_audit import audit_chain
from issue13_lab_l1_official_pdf_audit import (
    ENGINE, EXPECTED_SHA256, PERIOD, TIER,
)


def page(n, total, text):
    return {"page": n, "page_count": total, "pdf_sha256": EXPECTED_SHA256,
            "engine": ENGINE, "period": PERIOD, "tier": TIER, "text": text}


def write_batch(root, start, rows, request="123456"):
    target = root / f"l1-pages-{start}-{request}.jsonl"
    target.write_text("".join(json.dumps(row) + "\n" for row in rows),
                      encoding="utf-8")
    return target


class ChainTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def test_two_batches_complete_structural_only(self):
        write_batch(self.root, 1, [page(i, 6, f"AB{i:08d}") for i in range(1, 5)])
        write_batch(self.root, 5, [page(i, 6, f"AB{i:08d}") for i in range(5, 7)])
        result = audit_chain(self.root)
        self.assertEqual(result["pages"], 6)
        self.assertEqual(result["batches"], 2)
        self.assertEqual(result["page_order"], "MONOTONIC")
        self.assertEqual(result["global_not_win_authority"], "HOLD")

    def test_missing_middle_batch_rejected(self):
        write_batch(self.root, 1, [page(i, 9, f"AB{i:08d}") for i in range(1, 5)])
        write_batch(self.root, 9, [page(9, 9, "AB00000009")])
        with self.assertRaisesRegex(ValueError, "L1_CHAIN_GAP_OR_OVERLAP"):
            audit_chain(self.root)

    def test_duplicate_start_rejected(self):
        write_batch(self.root, 1, [page(i, 4, f"AB{i:08d}") for i in range(1, 5)])
        write_batch(self.root, 1, [page(i, 4, f"AB{i:08d}") for i in range(1, 5)], "999999")
        with self.assertRaisesRegex(ValueError, "L1_CHAIN_GAP_OR_OVERLAP"):
            audit_chain(self.root)

    def test_incomplete_nonterminal_batch_rejected(self):
        write_batch(self.root, 1, [page(1, 5, "AB00000001")])
        with self.assertRaisesRegex(ValueError, "L1_CHAIN_PARTIAL_BATCH"):
            audit_chain(self.root)

    def test_page_count_drift_rejected(self):
        write_batch(self.root, 1, [page(i, 6, f"AB{i:08d}") for i in range(1, 5)])
        write_batch(self.root, 5, [page(i, 7, f"AB{i:08d}") for i in range(5, 8)])
        with self.assertRaisesRegex(ValueError, "L1_CHAIN_PAGE_COUNT_DRIFT"):
            audit_chain(self.root)

    def test_intra_page_sort_inversion_rejected(self):
        write_batch(self.root, 1, [page(1, 1, "CD12345678 AB12345678")])
        with self.assertRaisesRegex(ValueError, "L1_BATCH_INTRA_PAGE_SORT_UNPROVEN"):
            audit_chain(self.root)

    def test_duplicate_json_field_rejected(self):
        (self.root / "l1-pages-1-123456.jsonl").write_text(
            '{"page":1,"page":2}\n', encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "DUPLICATE_PAGE_EVIDENCE_FIELD"):
            audit_chain(self.root)

    def test_over_budget_line_rejected(self):
        (self.root / "l1-pages-1-123456.jsonl").write_bytes(b"x" * 1000001 + b"\n")
        with self.assertRaisesRegex(ValueError, "L1_CHAIN_JSONL_LINE_BUDGET"):
            audit_chain(self.root)

    def test_symlink_and_unexpected_file_rejected(self):
        write_batch(self.root, 1, [page(1, 1, "AB12345678")])
        (self.root / "untrusted.txt").write_text("x", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "L1_CHAIN_UNEXPECTED_ENTRY"):
            audit_chain(self.root)
        (self.root / "untrusted.txt").unlink()
        (self.root / "l1-pages-2-123456.jsonl").symlink_to(
            self.root / "l1-pages-1-123456.jsonl")
        with self.assertRaisesRegex(ValueError, "L1_CHAIN_UNEXPECTED_ENTRY"):
            audit_chain(self.root)

    def test_cross_batch_unicode_ambiguity_rejected(self):
        write_batch(self.root, 1, [page(i, 5, f"AB{i:08d}") for i in range(1, 5)])
        write_batch(self.root, 5, [page(5, 5, "ＡＢ１２３４５６７８")])
        with self.assertRaisesRegex(ValueError, "UNICODE_COMPATIBILITY_TOKEN_AMBIGUITY"):
            audit_chain(self.root)


if __name__ == "__main__":
    unittest.main()
