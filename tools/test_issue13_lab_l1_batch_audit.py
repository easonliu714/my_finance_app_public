import unittest
from issue13_lab_l1_batch_audit import audit_batch
from issue13_lab_l1_official_pdf_audit import ENGINE, EXPECTED_SHA256, PERIOD, TIER


def page(n, count, text):
    return {"page": n, "page_count": count, "pdf_sha256": EXPECTED_SHA256,
            "engine": ENGINE, "period": PERIOD, "tier": TIER, "text": text}


class BatchTest(unittest.TestCase):
    def test_partial_never_authorizes_not_win(self):
        result = audit_batch([page(3, 8, "AB12345678"),
                              page(4, 8, "CD12345678")], first=3)
        self.assertEqual(result["global_not_win"], "HOLD")
        self.assertEqual(result["full_page_coverage"], "HOLD")

    def test_intra_page_inversion_rejected(self):
        with self.assertRaisesRegex(ValueError, "L1_BATCH_INTRA_PAGE_SORT_UNPROVEN"):
            audit_batch([page(1, 1, "CD12345678 AB12345678")], first=1)

    def test_missing_page(self):
        with self.assertRaisesRegex(ValueError, "L1_BATCH_RANGE_ORDER"):
            audit_batch([page(2, 8, "AB12345678")], first=1)

    def test_over_four_pages(self):
        with self.assertRaisesRegex(ValueError, "L1_BATCH_PAGE_BUDGET"):
            audit_batch([page(i, 8, f"AB{i:08d}") for i in range(1, 6)], first=1)

    def test_wrong_hash(self):
        row = page(1, 8, "AB12345678")
        row["pdf_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "L1_BATCH_SOURCE_SCOPE"):
            audit_batch([row], first=1)

    def test_unicode_compatibility(self):
        with self.assertRaisesRegex(ValueError, "UNICODE_COMPATIBILITY_TOKEN_AMBIGUITY"):
            audit_batch([page(1, 8, "ＡＢ１２３４５６７８")], first=1)

    def test_duplicate(self):
        with self.assertRaisesRegex(ValueError, "L1_BATCH_DUPLICATE"):
            audit_batch([page(1, 8, "AB12345678 AB12345678")], first=1)

    def test_sort_inversion(self):
        with self.assertRaisesRegex(ValueError, "L1_BATCH_SORT_UNPROVEN"):
            audit_batch([page(1, 8, "CD12345678"),
                         page(2, 8, "AB12345678")], first=1)

    def test_page_text_limit(self):
        with self.assertRaisesRegex(ValueError, "L1_BATCH_TEXT_BUDGET"):
            audit_batch([page(1, 8, "AB12345678" + "x" * 250000)], first=1)


if __name__ == "__main__":
    unittest.main()
