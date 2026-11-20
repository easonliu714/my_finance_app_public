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
  @Test fun retiredIdReusedCannotPublishStaleRead() {
    val cache = mutableMapOf<String, Map<String, Any>>()
    val epochs = mutableMapOf<String, Long>()
    val oldEpoch = LabL1NativePageCacheGuard.beginVersionedRead("reused", cache, epochs)
    LabL1NativePageCacheGuard.retire("reused", cache, epochs)
    val newEpoch = LabL1NativePageCacheGuard.beginVersionedRead("reused", cache, epochs)
    assertTrue(newEpoch > oldEpoch)
    assertFalse(LabL1NativePageCacheGuard.publishIfCurrent(
      "reused", oldEpoch, mapOf("pageNumber" to 1), cache, epochs, setOf("reused")
    ))
    assertTrue(cache.isEmpty())
  }

  @Test fun exhaustedEpochCannotWrapAndReplayOldRead() {
    val cache = mutableMapOf<String, Map<String, Any>>()
    val epochs = mutableMapOf("draw" to Long.MAX_VALUE)
    var rejected = false
    try {
      LabL1NativePageCacheGuard.beginVersionedRead("draw", cache, epochs)
    } catch (_: IllegalStateException) { rejected = true }
    assertTrue(rejected)
    assertFalse(LabL1NativePageCacheGuard.publishIfCurrent(
      "draw", 1L, mapOf("pageNumber" to 1), cache, epochs, setOf("draw")
    ))
    assertTrue(cache.isEmpty())
  }

  @Test fun nearExhaustedReadCannotReplayAfterRetireAndIdReuse() {
    val cache = mutableMapOf<String, Map<String, Any>>()
    val epochs = mutableMapOf("draw" to Long.MAX_VALUE - 2L)
    val issued = LabL1NativePageCacheGuard.beginVersionedRead("draw", cache, epochs)
    assertTrue(issued == Long.MAX_VALUE - 1L)
    LabL1NativePageCacheGuard.retire("draw", cache, epochs)
    // A reused live ID must not revive the retired last valid epoch.
    assertFalse(LabL1NativePageCacheGuard.publishIfCurrent(
      "draw", issued, mapOf("pageNumber" to 1), cache, epochs, setOf("draw")
    ))
    assertTrue(cache.isEmpty())
    var rejected = false
    try {
      LabL1NativePageCacheGuard.beginVersionedRead("draw", cache, epochs)
    } catch (_: IllegalStateException) { rejected = true }
    assertTrue(rejected)
    assertTrue(cache.isEmpty())
  }

  @Test fun maxMinusOneEpochRejectsWithoutMutatingCacheOrOtherRole() {
    val cache = mutableMapOf<String, Map<String, Any>>(
      "draw" to mapOf("pageNumber" to 4),
      "sorted" to mapOf("pageNumber" to 2)
    )
    val epochs = mutableMapOf("draw" to Long.MAX_VALUE - 1L, "sorted" to 3L)
    var rejected = false
    try {
      LabL1NativePageCacheGuard.beginVersionedRead("draw", cache, epochs)
    } catch (e: IllegalStateException) {
      rejected = e.message == "L1_SESSION_EPOCH_EXHAUSTED"
    }
    assertTrue(rejected)
    assertTrue(epochs["draw"] == Long.MAX_VALUE - 1L)
    assertTrue(cache["draw"]?.get("pageNumber") == 4)
    assertTrue(cache["sorted"]?.get("pageNumber") == 2)
    val sorted = LabL1NativePageCacheGuard.beginVersionedRead("sorted", cache, epochs)
    assertTrue(sorted == 4L)
    assertTrue(LabL1NativePageCacheGuard.publishIfCurrent(
      "sorted", sorted, mapOf("pageNumber" to 3), cache, epochs, setOf("sorted")
    ))
  }

  @Test fun reservedTombstoneNeverPublishesEvenIfLiveSessionIsReused() {
    val cache = mutableMapOf<String, Map<String, Any>>()
    val epochs = mutableMapOf("draw" to Long.MAX_VALUE)
    assertFalse(LabL1NativePageCacheGuard.publishIfCurrent(
      "draw", Long.MAX_VALUE, mapOf("pageNumber" to 1), cache, epochs, setOf("draw")
    ))
    assertTrue(cache.isEmpty())
    val other = LabL1NativePageCacheGuard.beginVersionedRead("sorted", cache, epochs)
    assertTrue(LabL1NativePageCacheGuard.publishIfCurrent(
      "sorted", other, mapOf("pageNumber" to 2), cache, epochs, setOf("sorted")
    ))
    assertTrue(cache.containsKey("sorted"))
  }
}
