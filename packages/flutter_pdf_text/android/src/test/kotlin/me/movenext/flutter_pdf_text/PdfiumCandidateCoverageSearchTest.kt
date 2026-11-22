package me.movenext.flutter_pdf_text

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class PdfiumCandidateCoverageSearchTest {
  private val first = "AA00000001"
  private val later = "AA00000005"
  private val pivot = "AA00000009"

  @Test fun disorderedPagesRecoverActualPositiveSkippedByBinarySearch() {
    val pages = listOf(listOf(first), listOf(pivot), listOf(later))
    val scanned = mutableListOf<Int>()
    val result = PdfiumCandidateCoverageSearch.search(listOf(later), 3) {
        page, _, full ->
      if (full) scanned.add(page)
      pages[page - 1]
    }
    assertTrue(result.fullCoverageScan)
    assertEquals(listOf(1, 2, 3), scanned)
    assertEquals(3, result.matchedPages[later])
    assertTrue(result.unresolved.isEmpty())
  }

  @Test fun binaryPositiveDoesNotRequireCostlyFullDocumentScan() {
    val pages = listOf(listOf(first), listOf(pivot), listOf(later))
    var fullReads = 0
    val result = PdfiumCandidateCoverageSearch.search(listOf(pivot), 3) {
        page, _, full ->
      if (full) fullReads++
      pages[page - 1]
    }
    assertEquals(2, result.matchedPages[pivot])
    assertFalse(result.fullCoverageScan)
    assertEquals(0, fullReads)
    assertTrue(result.unresolved.isEmpty())
  }

  @Test fun trueMissIsNotPromotedToAnAttestedNegative() {
    val pages = listOf(listOf(first), listOf(pivot), listOf(later))
    val reads = mutableListOf<Int>()
    val missing = "AA00000007"
    val result = PdfiumCandidateCoverageSearch.search(listOf(missing), 3) {
        page, _, full ->
      if (full) reads.add(page)
      pages[page - 1]
    }
    assertEquals(listOf(1, 2, 3), reads)
    assertTrue(result.fullCoverageScan)
    assertEquals(setOf(missing), result.unresolved)
    assertTrue(result.matchedPages.isEmpty())
    // Worker must send HOLD, never status=complete for this outcome.
  }

  @Test fun multipleMissesShareExactlyOneGlobalPass() {
    val pages = listOf(listOf(first), listOf(pivot), listOf(later))
    val missing = "AA00000007"
    val reads = mutableListOf<Int>()
    val result = PdfiumCandidateCoverageSearch.search(
      listOf(later, missing), 3
    ) { page, _, full ->
      if (full) reads.add(page)
      pages[page - 1]
    }
    assertEquals(listOf(1, 2, 3), reads)
    assertEquals(3, result.matchedPages[later])
    assertEquals(setOf(missing), result.unresolved)
  }

  @Test fun brokenPageDuringFullScanNeverReturnsPartialCoverage() {
    val pages = listOf(listOf(first), listOf(pivot), emptyList())
    var rejected = false
    try {
      PdfiumCandidateCoverageSearch.search(listOf(later), 3) {
          page, _, _ -> pages[page - 1]
      }
    } catch (e: IllegalStateException) {
      rejected = e.message == "PDFIUM_COVERAGE_PAGE_UNREADABLE_HOLD"
    }
    assertTrue(rejected)
  }

  @Test fun nativePdfiumExceptionDuringCoveragePropagatesToWorkerHold() {
    var rejected = false
    try {
      PdfiumCandidateCoverageSearch.search(listOf(later), 3) {
          page, _, full ->
        if (full && page == 3) throw IllegalStateException("NATIVE_PAGE_OPEN_FAILED")
        listOf(if (page == 2) pivot else first)
      }
    } catch (e: IllegalStateException) {
      rejected = e.message == "NATIVE_PAGE_OPEN_FAILED"
    }
    assertTrue(rejected)
  }

  @Test fun malformedCandidateUniverseRejectedBeforeNativeRead() {
    var called = false
    var rejected = false
    try {
      PdfiumCandidateCoverageSearch.search(listOf(first, first), 3) {
          _, _, _ ->
        called = true
        listOf(first)
      }
    } catch (e: IllegalArgumentException) {
      rejected = e.message == "PDFIUM_SEARCH_CANDIDATES_INVALID"
    }
    assertTrue(rejected)
    assertFalse(called)
  }
}
