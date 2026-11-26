package me.movenext.flutter_pdf_text

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** C22 synthetic sorted-page completeness contract; NOT a global PDF proof. */
class PlatformCandidateCompletionGateTest {
  private val first = "AB12345678"
  private val last = "CD87654321"
  private val requested = listOf(first, last)

  @Test fun allExactPageBackedPositivesMayComplete() {
    assertTrue(PlatformCandidateCompletionGate.allCandidatesPositivelyMatched(
      requested, setOf(last, first), mapOf(first to 1, last to 87000), 87000))
  }

  @Test fun partialOrZeroSearchMustRemainUnknownEvenWithValidPage() {
    assertFalse(PlatformCandidateCompletionGate.allCandidatesPositivelyMatched(
      requested, setOf(first), mapOf(first to 1), 87000))
    assertFalse(PlatformCandidateCompletionGate.allCandidatesPositivelyMatched(
      requested, emptySet(), emptyMap(), 87000))
  }

  @Test fun forgedForeignOrMissingPageEvidenceCannotComplete() {
    assertFalse(PlatformCandidateCompletionGate.allCandidatesPositivelyMatched(
      requested, setOf(first, "EF00000001"),
      mapOf(first to 1, "EF00000001" to 2), 87000))
    assertFalse(PlatformCandidateCompletionGate.allCandidatesPositivelyMatched(
      requested, setOf(first, last), mapOf(first to 1), 87000))
    assertFalse(PlatformCandidateCompletionGate.allCandidatesPositivelyMatched(
      requested, setOf(first, last), mapOf(first to 1, last to 87001), 87000))
  }

  @Test fun nonCanonicalCandidateUniverseMustRemainUnknownEvenWhenPageBacked() {
    for (malformed in listOf(
      "ab12345678", "AB1234567", "AB123456789",
      "AB 12345678", "AB12345678\\n", "AB12345678X"
    )) {
      assertFalse(PlatformCandidateCompletionGate.allCandidatesPositivelyMatched(
        listOf(malformed), setOf(malformed), mapOf(malformed to 1), 87000))
    }
    assertFalse(PlatformCandidateCompletionGate.allCandidatesPositivelyMatched(
      listOf(first, "AB 12345678"), setOf(first, "AB 12345678"),
      mapOf(first to 1, "AB 12345678" to 2), 87000))
  }

  @Test fun duplicateCandidateAndInvalidPageCountCannotComplete() {
    assertFalse(PlatformCandidateCompletionGate.allCandidatesPositivelyMatched(
      listOf(first, first), setOf(first), mapOf(first to 1), 87000))
    assertFalse(PlatformCandidateCompletionGate.allCandidatesPositivelyMatched(
      requested, setOf(first, last), mapOf(first to 1, last to 2), 0))
  }
}
