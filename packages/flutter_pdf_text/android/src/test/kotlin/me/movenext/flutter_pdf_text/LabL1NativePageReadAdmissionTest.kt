package me.movenext.flutter_pdf_text

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LabL1NativePageReadAdmissionTest {
  private data class Document(val pages: Int)

  private fun admission(
    sessionId: String,
    pageNumber: Int,
    structured: Boolean,
    verified: Boolean,
    documents: Map<String, Document>,
    cache: MutableMap<String, Map<String, Any>>,
    epochs: MutableMap<String, Long>,
    readCount: (Document) -> Int = { it.pages }
  ) = LabL1NativePageReadAdmission.admit(
    sessionId, pageNumber, structured, verified,
    documents, cache, epochs, readCount
  )

  @Test fun validVerifiedReadKeepsItsEpochAndOtherRole() {
    val docs = mapOf("draw" to Document(77_000), "sorted" to Document(77_000))
    val cache = mutableMapOf<String, Map<String, Any>>(
      "draw" to mapOf("pageNumber" to 1),
      "sorted" to mapOf("pageNumber" to 4)
    )
    val epochs = mutableMapOf("draw" to 5L, "sorted" to 3L)
    val result = admission("draw", 77_000, true, true, docs, cache, epochs)
    assertTrue(result is LabL1NativePageReadAdmission.Outcome.Ready)
    result as LabL1NativePageReadAdmission.Outcome.Ready
    assertEquals(77_000, result.pageCount)
    assertEquals(6L, result.epoch)
    assertFalse(cache.containsKey("draw"))
    assertTrue(cache.containsKey("sorted"))
    assertEquals(3L, epochs["sorted"])
  }

  @Test fun epochExhaustionReturnsExplicitHoldAndCannotReplayCachedToken() {
    val cache = mutableMapOf<String, Map<String, Any>>(
      "draw" to mapOf("pageNumber" to 1)
    )
    val epochs = mutableMapOf("draw" to Long.MAX_VALUE - 1L)
    val result = admission(
      "draw", 1, true, true, mapOf("draw" to Document(77_000)),
      cache, epochs
    )
    assertEquals(
      "L1_PAGE_READ_EPOCH_HOLD",
      (result as LabL1NativePageReadAdmission.Outcome.Hold).code
    )
    assertTrue(result.retire)
    // Plugin retires custody on this HOLD before responding to Flutter.
    LabL1NativePageCacheGuard.retire("draw", cache, epochs)
    assertFalse(cache.containsKey("draw"))
    assertEquals(Long.MAX_VALUE, epochs["draw"])
  }

  @Test fun throwingNativePageCountReturnsHoldAndLeavesOtherRoleUntouched() {
    val cache = mutableMapOf<String, Map<String, Any>>(
      "draw" to mapOf("pageNumber" to 3),
      "sorted" to mapOf("pageNumber" to 7)
    )
    val epochs = mutableMapOf("draw" to 1L, "sorted" to 9L)
    val docs = mapOf("draw" to Document(77_000), "sorted" to Document(77_000))
    val result = admission("draw", 2, true, true, docs, cache, epochs) {
      throw IllegalStateException("injected native getPageCount failure")
    }
    assertEquals(
      "PDFIUM_PAGE_COUNT_FAILED",
      (result as LabL1NativePageReadAdmission.Outcome.Hold).code
    )
    assertTrue(result.retire)
    assertFalse(cache.containsKey("draw"))
    assertTrue(cache.containsKey("sorted"))
    assertEquals(9L, epochs["sorted"])
  }

  @Test fun outOfRangeAndMissingSessionReturnBoundedHoldWithoutReadOrReplay() {
    val cache = mutableMapOf<String, Map<String, Any>>(
      "draw" to mapOf("pageNumber" to 1)
    )
    val epochs = mutableMapOf<String, Long>()
    val docs = mapOf("draw" to Document(77_000))
    val bad = admission("draw", 77_001, true, true, docs, cache, epochs)
    assertEquals(
      "PDFIUM_PAGE_OUT_OF_RANGE",
      (bad as LabL1NativePageReadAdmission.Outcome.Hold).code
    )
    assertFalse(bad.retire)
    assertFalse(cache.containsKey("draw"))
    val missing = admission("missing", 1, true, true, docs, cache, epochs)
    assertEquals(
      "PDFIUM_SESSION_NOT_FOUND",
      (missing as LabL1NativePageReadAdmission.Outcome.Hold).code
    )
    assertFalse(missing.retire)
    assertFalse(cache.containsKey("missing"))
  }

  @Test fun plainTextVerifiedReadAdvancesEpochAndGenericDoesNot() {
    val docs = mapOf("draw" to Document(77_000), "generic" to Document(2))
    val cache = mutableMapOf<String, Map<String, Any>>(
      "draw" to mapOf("tokens" to listOf("AB12345678"))
    )
    val epochs = mutableMapOf("draw" to 7L)
    val plain = admission("draw", 1, false, true, docs, cache, epochs)
    assertTrue(plain is LabL1NativePageReadAdmission.Outcome.Ready)
    assertEquals(8L, (plain as LabL1NativePageReadAdmission.Outcome.Ready).epoch)
    assertFalse(cache.containsKey("draw"))
    val generic = admission("generic", 1, false, false, docs, cache, epochs)
    assertTrue(generic is LabL1NativePageReadAdmission.Outcome.Ready)
    assertEquals(null, (generic as LabL1NativePageReadAdmission.Outcome.Ready).epoch)
    assertFalse(epochs.containsKey("generic"))
    assertNotNull(docs["generic"])
  }

  @Test fun verifiedRoleRejectsTruncatedAndInflatedOfficialPageCount() {
    val docs = mapOf("draw" to Document(77_000), "sorted" to Document(77_000))
    val epochs = mutableMapOf("draw" to 8L, "sorted" to 5L)
    val cache = mutableMapOf<String, Map<String, Any>>(
      "draw" to mapOf("pageNumber" to 1),
      "sorted" to mapOf("pageNumber" to 2)
    )
    for (badCount in listOf(1, 2, 76_999, 77_001, 100_000)) {
      val held = admission(
        "draw", 1, true, true, docs, cache, epochs
      ) { badCount }
      assertTrue(held is LabL1NativePageReadAdmission.Outcome.Hold)
      held as LabL1NativePageReadAdmission.Outcome.Hold
      assertEquals("L1_OWNER_PDFIUM_PAGE_COUNT_MISMATCH_HOLD", held.code)
      assertTrue(held.retire)
      assertFalse(cache.containsKey("draw"))
      assertTrue(cache.containsKey("sorted"))
      assertEquals(5L, epochs["sorted"])
    }
  }

  @Test fun verifiedPlainTextAlsoRejectsWrongCountWithoutReturningBytes() {
    val cache = mutableMapOf<String, Map<String, Any>>()
    val epochs = mutableMapOf<String, Long>()
    val held = admission(
      "sorted", 1, false, true, mapOf("sorted" to Document(76_999)),
      cache, epochs
    )
    assertTrue(held is LabL1NativePageReadAdmission.Outcome.Hold)
    held as LabL1NativePageReadAdmission.Outcome.Hold
    assertEquals("L1_OWNER_PDFIUM_PAGE_COUNT_MISMATCH_HOLD", held.code)
    assertTrue(held.retire)
  }

  @Test fun exactOfficialCountPassesAndGenericSmallPdfStillWorks() {
    val docs = mapOf("draw" to Document(77_000), "generic" to Document(2))
    val cache = mutableMapOf<String, Map<String, Any>>()
    val epochs = mutableMapOf<String, Long>()
    val role = admission("draw", 77_000, true, true, docs, cache, epochs)
    assertTrue(role is LabL1NativePageReadAdmission.Outcome.Ready)
    assertEquals(
      LabL1MayJuneOwnerAttestedBytePair.expectedPageCount,
      (role as LabL1NativePageReadAdmission.Outcome.Ready).pageCount
    )
    val generic = admission("generic", 2, false, false, docs, cache, epochs)
    assertTrue(generic is LabL1NativePageReadAdmission.Outcome.Ready)
    assertEquals(
      2, (generic as LabL1NativePageReadAdmission.Outcome.Ready).pageCount
    )
    assertFalse(epochs.containsKey("generic"))
  }

  @Test fun emptyNativePageCountNeverReturnsReadyOrPublishesTokens() {
    val cache = mutableMapOf<String, Map<String, Any>>()
    val epochs = mutableMapOf<String, Long>()
    val held = admission("draw", 1, true, true,
      mapOf("draw" to Document(0)), cache, epochs)
    assertEquals(
      "PDFIUM_PAGE_COUNT_INVALID",
      (held as LabL1NativePageReadAdmission.Outcome.Hold).code
    )
    assertTrue(held.retire)
    assertTrue(cache.isEmpty())
  }
}
