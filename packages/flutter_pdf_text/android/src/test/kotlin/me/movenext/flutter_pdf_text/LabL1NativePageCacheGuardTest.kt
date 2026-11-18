package me.movenext.flutter_pdf_text

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LabL1NativePageCacheGuardTest {
  @Test fun newReadDiscardsPriorSuccessfulProbe() {
    val pages = mutableMapOf<String, Map<String, Any>>(
      "draw" to mapOf("tokens" to listOf("AB12345678")),
      "sorted" to mapOf("tokens" to listOf("AB12345678"))
    )
    LabL1NativePageCacheGuard.beginRead("draw", pages)
    assertFalse(pages.containsKey("draw"))
    assertTrue(pages.containsKey("sorted"))
  }

  @Test fun missingSessionReadNeverRestoresOldProbe() {
    val pages = mutableMapOf<String, Map<String, Any>>()
    LabL1NativePageCacheGuard.beginRead("closed", pages)
    assertFalse(pages.containsKey("closed"))
  }

  @Test fun repeatedInvalidReadCannotReplayEarlierPage() {
    val pages = mutableMapOf("draw" to mapOf<String, Any>("pageNumber" to 1))
    LabL1NativePageCacheGuard.beginRead("draw", pages)
    LabL1NativePageCacheGuard.beginRead("draw", pages)
    assertTrue(pages.isEmpty())
  }
}
