package me.movenext.flutter_pdf_text

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** C28 deterministic native JVM regressions; not Android or 87K global proof. */
class PlatformInvoicePageTokenExtractorTest {
  @Test fun sortedDocumentOrderRemainsValidForObservedGate() {
    val tokens = PlatformInvoicePageTokenExtractor.extractInDocumentOrder(
      "AA00000001 AB00000002")
    assertEquals(listOf("AA00000001", "AB00000002"), tokens)
    assertTrue(PlatformObservedPageOrderGate(87000).observe(43500, tokens))
  }

  @Test fun invertedSourceOrderCannotBeLaunderedBySorting() {
    val tokens = PlatformInvoicePageTokenExtractor.extractInDocumentOrder(
      "AC00000003 AB00000002")
    assertEquals(listOf("AC00000003", "AB00000002"), tokens)
    assertFalse("C28_SOURCE_ORDER_INVERSION_MUST_FAIL_CLOSED",
      PlatformObservedPageOrderGate(87000).observe(43500, tokens))
  }

  @Test fun repeatedRowsRemainVisibleToPageIdentity() {
    val tokens = PlatformInvoicePageTokenExtractor.extractInDocumentOrder(
      "AA00000001 AA00000001 AB00000002")
    assertEquals(listOf("AA00000001", "AA00000001", "AB00000002"), tokens)
    val gate = PlatformObservedPageOrderGate(87000)
    assertTrue(gate.observe(10, tokens))
    assertFalse(gate.observe(10, listOf("AA00000001", "AB00000002")))
  }

  @Test fun whitespaceAndCaseNormalizationPreservesOrder() {
    assertEquals(listOf("AB12345678", "AC12345679"),
      PlatformInvoicePageTokenExtractor.extractInDocumentOrder(
        "ab 12345678\nac 12345679"))
  }

  @Test fun embeddedAlphanumericFalseHitsAreRejected() {
    assertEquals(listOf("AB00000002"),
      PlatformInvoicePageTokenExtractor.extractInDocumentOrder(
        "XAA00000001Y AB00000002"))
  }
}
