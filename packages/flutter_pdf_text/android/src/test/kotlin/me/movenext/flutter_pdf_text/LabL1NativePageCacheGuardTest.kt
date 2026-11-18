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
  @Test fun lateFirstReadCannotReplayAfterNewerFailedRead() {
    val cache = mutableMapOf<String, Map<String, Any>>()
    val epochs = mutableMapOf<String, Long>()
    val first = LabL1NativePageCacheGuard.beginVersionedRead("draw", cache, epochs)
    val second = LabL1NativePageCacheGuard.beginVersionedRead("draw", cache, epochs)
    assertFalse(LabL1NativePageCacheGuard.publishIfCurrent(
      "draw", first, mapOf("pageNumber" to 1), cache, epochs, setOf("draw")
    ))
    assertTrue(cache.isEmpty())
    assertTrue(second > first)
  }

  @Test fun retiredSessionRejectsLateSuccessAndOtherSessionSurvives() {
    val cache = mutableMapOf<String, Map<String, Any>>()
    val epochs = mutableMapOf<String, Long>()
    val draw = LabL1NativePageCacheGuard.beginVersionedRead("draw", cache, epochs)
    val sorted = LabL1NativePageCacheGuard.beginVersionedRead("sorted", cache, epochs)
    LabL1NativePageCacheGuard.retire("draw", cache, epochs)
    assertFalse(LabL1NativePageCacheGuard.publishIfCurrent(
      "draw", draw, mapOf("tokens" to listOf("AB12345678")), cache, epochs, setOf("sorted")
    ))
    assertTrue(LabL1NativePageCacheGuard.publishIfCurrent(
      "sorted", sorted, mapOf("tokens" to listOf("AB12345678")), cache, epochs, setOf("sorted")
    ))
    assertFalse(cache.containsKey("draw"))
    assertTrue(cache.containsKey("sorted"))
  }

  @Test fun closedSessionCannotPublishEvenWithMatchingEpoch() {
    val cache = mutableMapOf<String, Map<String, Any>>()
    val epochs = mutableMapOf<String, Long>()
    val epoch = LabL1NativePageCacheGuard.beginVersionedRead("draw", cache, epochs)
    assertFalse(LabL1NativePageCacheGuard.publishIfCurrent(
      "draw", epoch, mapOf("pageNumber" to 1), cache, epochs, emptySet()
    ))
    assertTrue(cache.isEmpty())
  }
}

