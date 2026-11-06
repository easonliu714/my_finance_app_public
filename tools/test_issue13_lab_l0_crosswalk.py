"""Positive/negative L0 parser tests; synthetic fixtures are not official PDF proof."""
import unittest
from issue13_lab_l0_crosswalk import G, M, K, W, D, SIGNER, APP_ID, crosswalk


def fixtures():
    lab = {
        "pubspec.yaml": "version: 4.20.18+476\n",
        G: "compileSdkVersion 36\nminSdkVersion 23\n"
           "implementation 'io.legere:pdfiumandroid:2.0.1'\n"
           "implementation 'com.tom-roush:pdfbox-android:2.0.17.0'\n",
        M: '<service android:process=":platform_pdf_probe" />',
        K+"PdfiumCandidateWorkerService.kt": "class Worker {}",
        K+"PlatformPdfProbeService.kt": "import android.graphics.pdf.PdfRenderer",
        W: 'applicationId = "'+APP_ID+'"\nLAB_SIGNER_SHA256='+SIGNER,
        D: SIGNER,
    }
    prod = {
        "pubspec.yaml": "version: 4.20.37+495\n",
        G: "compileSdkVersion 36\nminSdkVersion 23\n"
           "implementation 'io.legere:pdfiumandroid:1.0.35'\n"
           "implementation 'com.tom-roush:pdfbox-android:2.0.27.0'\n",
        M: '<service android:process=":platform_candidate_worker" />',
        K+"PdfiumCandidateWorkerService.kt": "class Worker {}",
    }
    return lab, prod


class CrosswalkTest(unittest.TestCase):
    def test_divergence_is_not_integration_pass(self):
        lab, prod = fixtures()
        r = crosswalk(lab, prod, "a"*40, "b"*40)
        self.assertFalse(r["version_equal"])
        self.assertFalse(r["pdfium_equal"])
        self.assertFalse(r["pdfbox_equal"])
        self.assertEqual(r["production_integration"], "HOLD")
        self.assertFalse(r["official_pdf_revalidated"])

    def test_identity_drift_rejected(self):
        lab, prod = fixtures()
        lab[W] = lab[W].replace(APP_ID, "com.example.my_finance_app")
        with self.assertRaisesRegex(ValueError, "applicationId"):
            crosswalk(lab, prod, "a"*40, "b"*40)

    def test_signer_drift_rejected(self):
        lab, prod = fixtures()
        lab[W] = lab[W].replace(SIGNER, "0"*64)
        with self.assertRaisesRegex(ValueError, "signer"):
            crosswalk(lab, prod, "a"*40, "b"*40)

    def test_missing_production_source_rejected(self):
        lab, prod = fixtures()
        del prod[G]
        with self.assertRaisesRegex(ValueError, "missing required source"):
            crosswalk(lab, prod, "a"*40, "b"*40)

    def test_missing_isolated_process_rejected(self):
        lab, prod = fixtures()
        lab[M] = '<service android:process=":pdfium_open_probe" />'
        with self.assertRaisesRegex(ValueError, "isolated platform process"):
            crosswalk(lab, prod, "a"*40, "b"*40)


if __name__ == "__main__":
    unittest.main()
