package me.movenext.flutter_pdf_text

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LabL1PageTokenExtractorTest {
  @Test fun extractsFull10FromActualPageTextShape() {
    val page = "header\\nAB12345678  CD87654321\\nfooter"
    assertEquals(listOf("AB12345678", "CD87654321"),
      LabL1PageTokenExtractor.extract(page.replace("\\n", "\n")))
  }

  @Test fun rejectsEmbeddedPartialAndMalformedTokens() {
    assertEquals(emptyList<String>(), LabL1PageTokenExtractor.extract(
      "XAB12345678 AB123456789 AB1234567 ab12345678 AB12345678X"))
  }

  @Test fun doesNotDeduplicateOrClaimSortedOrder() {
    assertEquals(listOf("AB12345678", "AB12345678"),
      LabL1PageTokenExtractor.extract("AB12345678 AB12345678"))
  }

  @Test fun oversizedPageFailsClosed() {
    var rejected = false
    try { LabL1PageTokenExtractor.extract("x".repeat(2_000_001)) }
    catch (_: IllegalArgumentException) { rejected = true }
    assertTrue(rejected)
  }
}
