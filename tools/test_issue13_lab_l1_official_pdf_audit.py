"""L1 negative/positive contract tests use synthetic data, never official PASS."""
import hashlib
import tempfile
import unittest
from pathlib import Path

from issue13_lab_l1_official_pdf_audit import (
    ENGINE, EXPECTED_SHA256, PERIOD, TIER, audit_pages, pdf_identity, read_jsonl,
)


def page(number, total, text):
    return {"page": number, "page_count": total,
            "pdf_sha256": EXPECTED_SHA256, "engine": ENGINE,
            "period": PERIOD, "tier": TIER, "text": text}


class L1AuditTest(unittest.TestCase):
    def test_synthetic_sorted_pages_only_structural_audit_not_verdict(self):
        result = audit_pages([page(1, 2, "AB12345678 CD12345678"),
                              page(2, 2, "EF12345678 GH12345678")])
        self.assertEqual(result["canonical_tokens"], 4)
        self.assertEqual(result["global_not_win_authority"], "HOLD")
        self.assertEqual(result["extraction_completeness"], "UNATTESTED")

    def test_missing_page_rejected(self):
        with self.assertRaisesRegex(ValueError, "INCOMPLETE_PAGE_COVERAGE"):
            audit_pages([page(1, 2, "AB12345678")])

    def test_out_of_order_pages_rejected(self):
        with self.assertRaisesRegex(ValueError, "PAGE_COVERAGE_OR_ORDER_MISMATCH"):
            audit_pages([page(2, 2, "AB12345678")])

    def test_cross_page_sort_inversion_rejected(self):
        with self.assertRaisesRegex(ValueError, "GLOBAL_PAGE_SORT_ORDER_UNPROVEN"):
            audit_pages([page(1, 2, "CD12345678"), page(2, 2, "AB12345678")])

    def test_duplicate_invoice_rejected(self):
        with self.assertRaisesRegex(ValueError, "DUPLICATE_INVOICE_TOKEN"):
            audit_pages([page(1, 2, "AB12345678"), page(2, 2, "AB12345678")])

    def test_unicode_fullwidth_ambiguity_rejected(self):
        with self.assertRaisesRegex(ValueError, "UNICODE_COMPATIBILITY_TOKEN_AMBIGUITY"):
            audit_pages([page(1, 1, "ＡＢ１２３４５６７８ AB12345678")])

    def test_period_or_tier_mismatch_rejected(self):
        altered = page(1, 1, "AB12345678")
        altered["period"] = "115-05-06"
        with self.assertRaisesRegex(ValueError, "PAGE_EVIDENCE_SOURCE_OR_SCOPE_MISMATCH"):
            audit_pages([altered])

    def test_unexpected_field_rejected(self):
        altered = page(1, 1, "AB12345678")
        altered["verdict"] = "NOT_WIN"
        with self.assertRaisesRegex(ValueError, "PAGE_EVIDENCE_SCHEMA_MISMATCH"):
            audit_pages([altered])

    def test_streaming_pdf_identity_synthetic_injected_expectation_only(self):
        data = b"%PDF-1.7\nSYNTHETIC-TEST-ONLY\n%%EOF\n"
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "fake.pdf"
            path.write_bytes(data)
            result = pdf_identity(path, expected_bytes=len(data),
                                  expected_sha256=hashlib.sha256(data).hexdigest())
            self.assertEqual(result["bytes"], len(data))
            with self.assertRaisesRegex(ValueError, "PDF_OFFICIAL_BYTES_SHA_MISMATCH"):
                pdf_identity(path)

    def test_duplicate_json_keys_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "pages.jsonl"
            path.write_text('{"page":1,"page":2}\n', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "DUPLICATE_PAGE_EVIDENCE_FIELD"):
                list(read_jsonl(path))

    def test_page_text_embedded_in_lowercase_word_not_token(self):
        with self.assertRaisesRegex(ValueError, "PAGE_WITHOUT_CANONICAL_TOKENS"):
            audit_pages([page(1, 1, "abcAB12345678def")])

    def test_no_empty_page_is_accepted_as_complete(self):
        with self.assertRaisesRegex(ValueError, "PAGE_WITHOUT_CANONICAL_TOKENS"):
            audit_pages([page(1, 1, "cover page only")])


if __name__ == "__main__":
    unittest.main()
