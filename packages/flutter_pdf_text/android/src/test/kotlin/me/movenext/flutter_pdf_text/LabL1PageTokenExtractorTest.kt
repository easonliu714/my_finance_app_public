package me.movenext.flutter_pdf_text

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Regression for real PDFium Unicode text boundaries, not a source/award oracle. */
class LabL1UnicodeCombiningMarkBoundaryTest {
  private val invoice = "AB12345678"

  @Test fun validExactFull10AndPunctuationSeparatedTokensRemainReadable() {
    assertEquals(listOf(invoice), LabL1PageTokenExtractor.extract(invoice))
    assertEquals(
      listOf(invoice, "CD87654321"),
      LabL1PageTokenExtractor.extract("<$invoice>; CD87654321")
    )
    assertEquals(emptyList<String>(), LabL1PageTokenExtractor.extract("no invoice"))
  }

  @Test fun combiningMarksAdjacentToInvoiceCannotCreateSubstringFalsePositive() {
    // Mn (non-spacing), Mc (spacing-combining) and Me (enclosing) are
    // contiguous Unicode grapheme components, not invoice separators.
    for (mark in listOf("\u0301", "\u0903", "\u20DD")) {
      assertTrue(
        "Trailing combining mark must not yield Full-10",
        LabL1PageTokenExtractor.extract(invoice + mark).isEmpty()
      )
      assertTrue(
        "Leading combining mark must not yield Full-10",
        LabL1PageTokenExtractor.extract(mark + invoice).isEmpty()
      )
      assertEquals(
        listOf(invoice),
        LabL1PageTokenExtractor.extract("($invoice) ($mark" + invoice + ") ($invoice$mark)"))
    }
  }

  @Test fun letterAndDigitAdjacentFragmentsRemainRejected() {
    for (raw in listOf("Z$invoice", "$invoice" + "9", "字$invoice", "$invoice" + "字")) {
      assertTrue(LabL1PageTokenExtractor.extract(raw).isEmpty())
    }
  }

  @Test fun oversizedPdfiumTextRemainsFailClosed() {
    var rejected = false
    try {
      LabL1PageTokenExtractor.extract("X".repeat(2_000_001))
    } catch (e: IllegalArgumentException) {
      rejected = e.message == "L1_PAGE_TEXT_TOO_LARGE_HOLD"
    }
    assertTrue(rejected)
  }
}
