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
    assertTrue(result.positiveFallbackUsed)
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
    assertFalse(result.positiveFallbackUsed)
    assertEquals(0, fullReads)
    assertTrue(result.unresolved.isEmpty())
  }

  @Test fun positiveFallbackStopsBeforeUnrelatedUnreadablePages() {
    val pages = listOf(
      listOf(first), listOf(pivot), listOf(later), listOf(pivot),
      emptyList(), listOf(pivot), listOf(pivot)
    )
    val visitedInFallback = mutableListOf<Int>()
    val result = PdfiumCandidateCoverageSearch.search(listOf(later), pages.size) {
        page, _, full ->
      if (full) visitedInFallback.add(page)
      pages[page - 1]
    }
    assertEquals(3, result.matchedPages[later])
    assertEquals(listOf(1, 2, 3), visitedInFallback)
    assertTrue(result.positiveFallbackUsed)
    assertFalse(result.fullCoverageScan)
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

  @Test fun unreadableBinaryNeighborFallsBackToRealPositive() {
    // Page 4 brackets the candidate; speculative neighbor page 3 is blank.
    // A verified positive on page 1 must still be recovered by full fallback.
    val pages = listOf(listOf(later), listOf(first), emptyList(),
      listOf(first, pivot), listOf(first), listOf(first), listOf(first))
    val fullReads = mutableListOf<Int>()
    val result = PdfiumCandidateCoverageSearch.search(listOf(later), pages.size) {
        page, _, full ->
      if (full) fullReads.add(page)
      pages[page - 1]
    }
    assertEquals(1, result.matchedPages[later])
    assertEquals(listOf(1), fullReads)
    assertTrue(result.positiveFallbackUsed)
    assertFalse(result.fullCoverageScan)
    assertTrue(result.unresolved.isEmpty())
  }

  @Test fun unreadableBinaryNeighborCannotCertifyUnresolvedNegative() {
    val pages = listOf(listOf(first), listOf(first), emptyList(),
      listOf(first, pivot), listOf(first), listOf(first), listOf(first))
    val fullReads = mutableListOf<Int>()
    var rejected = false
    try {
      PdfiumCandidateCoverageSearch.search(listOf(later), pages.size) {
          page, _, full ->
        if (full) fullReads.add(page)
        pages[page - 1]
      }
    } catch (error: IllegalStateException) {
      rejected = error.message == "PDFIUM_COVERAGE_PAGE_UNREADABLE_HOLD"
    }
    assertTrue(rejected)
    assertEquals(listOf(1, 2, 3), fullReads)
  }

  @Test fun actualNativeBinaryNeighborFailureStillPropagates() {
    val pages = listOf(listOf(later), listOf(first), listOf(first),
      listOf(first, pivot), listOf(first), listOf(first), listOf(first))
    var fullScanStarted = false
    var rejected = false
    try {
      PdfiumCandidateCoverageSearch.search(listOf(later), pages.size) {
          page, _, full ->
        if (full) fullScanStarted = true
        if (!full && page == 3) {
          throw IllegalStateException("NATIVE_PAGE_OPEN_FAILED")
        }
        pages[page - 1]
      }
    } catch (error: IllegalStateException) {
      rejected = error.message == "NATIVE_PAGE_OPEN_FAILED"
    }
    assertTrue(rejected)
    assertFalse(fullScanStarted)
  }

  @Test fun unreadableBinaryPivotFallsBackToEarlierVerifiedPositive() {
    // Page 4 is an unrelated blank pivot; page 1 is an actual positive.
    // A binary pivot failure alone must not suppress that positive proof.
    val pages = listOf(listOf(later), listOf(first), listOf(first), emptyList(),
      listOf(first), listOf(first), listOf(first))
    val fallbackPages = mutableListOf<Int>()
    val result = PdfiumCandidateCoverageSearch.search(listOf(later), pages.size) {
        page, _, full ->
      if (full) fallbackPages.add(page)
      pages[page - 1]
    }
    assertEquals(1, result.matchedPages[later])
    assertEquals(listOf(1), fallbackPages)
    assertTrue(result.positiveFallbackUsed)
    assertFalse(result.fullCoverageScan)
    assertTrue(result.unresolved.isEmpty())
  }

  @Test fun unreadableBinaryPivotNeverCertifiesUnresolvedNegative() {
    val pages = listOf(listOf(first), listOf(first), listOf(first), emptyList(),
      listOf(first), listOf(first), listOf(first))
    val fallbackPages = mutableListOf<Int>()
    var rejected = false
    try {
      PdfiumCandidateCoverageSearch.search(listOf(later), pages.size) {
          page, _, full ->
        if (full) fallbackPages.add(page)
        pages[page - 1]
      }
    } catch (error: IllegalStateException) {
      rejected = error.message == "PDFIUM_COVERAGE_PAGE_UNREADABLE_HOLD"
    }
    assertTrue(rejected)
    assertEquals(listOf(1, 2, 3, 4), fallbackPages)
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
