"""Positive and negative tests for the CI-only release-AOT signer witness."""

import hashlib
import unittest

from c500_witness_signer_verify import (
    WitnessSignerError,
    verify_disposable_debug_signer,
)


class C500WitnessSignerVerifyTest(unittest.TestCase):
    def setUp(self):
        self.cert = bytes(range(256)) * 3
        self.digest = hashlib.sha256(self.cert).hexdigest()
        self.report = f"Signer #1 certificate SHA-256 digest: {self.digest}\n"

    def test_exact_single_debug_certificate_matches(self):
        verify_disposable_debug_signer(self.report, self.cert)

    def test_sha256_label_variant_is_accepted(self):
        verify_disposable_debug_signer(
            f"Signer #1 certificate SHA256 digest: {self.digest.upper()}\n",
            self.cert,
        )

    def test_mismatch_fails_closed(self):
        with self.assertRaisesRegex(WitnessSignerError, "SIGNER_MISMATCH"):
            verify_disposable_debug_signer(self.report, self.cert + b"x")

    def test_missing_certificate_line_fails_closed(self):
        with self.assertRaisesRegex(WitnessSignerError, "PARSE_OR_CARDINALITY"):
            verify_disposable_debug_signer("Signer #1 certificate SHA-1 digest: ab\n", self.cert)

    def test_multiple_signers_fail_closed(self):
        with self.assertRaisesRegex(WitnessSignerError, "PARSE_OR_CARDINALITY"):
            verify_disposable_debug_signer(
                self.report + f"Signer #2 certificate SHA-256 digest: {self.digest}\n",
                self.cert,
            )

    def test_wrong_signer_number_fails_closed(self):
        with self.assertRaisesRegex(WitnessSignerError, "PARSE_OR_CARDINALITY"):
            verify_disposable_debug_signer(
                f"Signer #2 certificate SHA-256 digest: {self.digest}\n", self.cert
            )

    def test_missing_debug_certificate_fails_closed(self):
        with self.assertRaisesRegex(WitnessSignerError, "DER_MISSING"):
            verify_disposable_debug_signer(self.report, b"")


if __name__ == "__main__":
    unittest.main()
