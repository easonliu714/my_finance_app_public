package me.movenext.flutter_pdf_text

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LabL1PrefixBoundsTest {
  private val identity = LabL1PrefixBounds.Identity(
    "115-07-08", "cloud500", "a".repeat(64), "pdf-renderer-v1", 512, 4
  )
  private fun proof(id: LabL1PrefixBounds.Identity = identity) =
    LabL1PrefixBounds.OrderProof(id, true, true, true, true)

  private fun sortedPages(): Map<Int, List<String>> = (1..512).associateWith { page ->
    val prefix = when {
      page <= 128 -> "AA"
      page <= 384 -> "AB"
      else -> "AC"
    }
    (0..3).map { "$prefix%08d".format((page - 1) * 4 + it) }
  }

  @Test fun coldBoundsAndWarmCacheStayWithinSameSource() {
    val pages = sortedPages()
    val finder = LabL1PrefixBounds()
    val cold = finder.locate(identity, "AB", proof()) { pages.getValue(it) }
    assertTrue(cold is LabL1PrefixBounds.Outcome.Range)
    cold as LabL1PrefixBounds.Outcome.Range
    assertEquals(129, cold.first)
    assertEquals(384, cold.last)
    assertTrue(cold.pageReads in 1..64)
    assertFalse(cold.cacheHit)
    assertTrue(cold.authoritative)
    val warm = finder.locate(identity, "AB", proof()) { error("warm cache read") }
    assertEquals(LabL1PrefixBounds.Outcome.Range(129, 384, 0, true, true), warm)
  }

  @Test fun coldTwoBoundsCanCostMoreReadsThanDirectBinary() {
    val pages = sortedPages()
    val target = "AB00000550"
    var directReads = 0
    var low = 1
    var high = identity.pageCount
    while (low <= high) {
      val mid = low + ((high - low) ushr 1)
      val tokens = pages.getValue(mid)
      directReads++
      when {
        target < tokens.first() -> high = mid - 1
        target > tokens.last() -> low = mid + 1
        else -> break
      }
    }
    val cold = LabL1PrefixBounds().locate(identity, "AB", proof()) { pages.getValue(it) }
      as LabL1PrefixBounds.Outcome.Range
    assertTrue("cold prefix bounds are not automatically faster", cold.pageReads > directReads)
  }

  @Test fun firstLastAndPrefixTransitionBoundaries() {
    val pages = sortedPages()
    val finder = LabL1PrefixBounds()
    val first = finder.locate(identity, "AA", proof()) { pages.getValue(it) }
      as LabL1PrefixBounds.Outcome.Range
    assertEquals(1, first.first)
    assertEquals(128, first.last)
    val tail = finder.locate(identity, "AC", proof()) { pages.getValue(it) }
      as LabL1PrefixBounds.Outcome.Range
    assertEquals(385, tail.first)
    assertEquals(512, tail.last)
  }

  @Test fun missingPrefixCannotBeNegativeWithoutFullOrderProof() {
    val pages = sortedPages().mapValues { (_, tokens) ->
      tokens.map { if (it.startsWith("AB")) "AC" + it.drop(2) else it }
    }
    val finder = LabL1PrefixBounds()
    val unknown = finder.locate(identity, "AB", null) { pages.getValue(it) }
    assertTrue(unknown is LabL1PrefixBounds.Outcome.Hold)
    assertEquals("L1_PREFIX_EMPTY_UNATTESTED", (unknown as LabL1PrefixBounds.Outcome.Hold).reason)
    assertTrue(finder.locate(identity, "AB", proof()) { pages.getValue(it) }
      is LabL1PrefixBounds.Outcome.Empty)
  }

  @Test fun unverifiedRangeIsOnlyDiagnosticAndNeverCached() {
    val pages = sortedPages()
    val finder = LabL1PrefixBounds()
    val first = finder.locate(identity, "AB", null) { pages.getValue(it) }
      as LabL1PrefixBounds.Outcome.Range
    val second = finder.locate(identity, "AB", null) { pages.getValue(it) }
      as LabL1PrefixBounds.Outcome.Range
    assertFalse(first.authoritative)
    assertFalse(second.cacheHit)
    assertTrue(second.pageReads > 0)
  }

  @Test fun malformedEmptyDuplicateAndShortPagesFailClosed() {
    val pages = sortedPages()
    val malformed = listOf(
      emptyList(),
      listOf("AB00000001", "AB00000001", "AB00000002", "AB00000003"),
      listOf("AB00000001"),
      listOf("AB00000001", "AB00000002", "AB00000003", "AB0000000X")
    )
    for (tokens in malformed) {
      val result = LabL1PrefixBounds().locate(identity, "AB", proof()) {
        if (it == 256) tokens else pages.getValue(it)
      }
      assertTrue(result is LabL1PrefixBounds.Outcome.Hold)
    }
  }

  @Test fun adjacentNonMonotonicPagesFailClosed() {
    val id = identity.copy(pageCount = 2, tokensPerPage = 2)
    val pages = mapOf(1 to listOf("AB00000001", "AB00000002"),
      2 to listOf("AA00000003", "AA00000004"))
    val result = LabL1PrefixBounds().locate(id, "AB", proof(id)) { pages.getValue(it) }
    assertEquals("L1_PREFIX_CROSS_PAGE_NONMONOTONIC",
      (result as LabL1PrefixBounds.Outcome.Hold).reason)
  }

  @Test fun staleShaAndParserVersionCannotReuseCache() {
    val pages = sortedPages()
    val finder = LabL1PrefixBounds()
    finder.locate(identity, "AB", proof()) { pages.getValue(it) }
    for (changed in listOf(identity.copy(sourceSha256 = "b".repeat(64)),
      identity.copy(parserVersion = "pdf-renderer-v2"))) {
      val result = finder.locate(changed, "AB", proof(changed)) { pages.getValue(it) }
        as LabL1PrefixBounds.Outcome.Range
      assertFalse(result.cacheHit)
      assertTrue(result.pageReads > 0)
    }
  }

  @Test fun corruptCacheAndIncompleteProofHoldWithoutReading() {
    val pages = sortedPages()
    val entries = mutableMapOf<LabL1PrefixBounds.Key, LabL1PrefixBounds.Entry>()
    val finder = LabL1PrefixBounds(entries)
    finder.locate(identity, "AB", proof()) { pages.getValue(it) }
    val key = LabL1PrefixBounds.Key(identity, "AB")
    entries[key] = entries.getValue(key).copy(first = 9999)
    val corrupted = finder.locate(identity, "AB", proof()) { error("must not read") }
    assertEquals("L1_PREFIX_CACHE_CORRUPT",
      (corrupted as LabL1PrefixBounds.Outcome.Hold).reason)
    val incomplete = proof().copy(fullCoverage = false)
    assertEquals("L1_PREFIX_ORDER_PROOF_INVALID",
      (finder.locate(identity, "AB", incomplete) { error("must not read") }
        as LabL1PrefixBounds.Outcome.Hold).reason)
  }

  @Test fun wrongPeriodTierSourceAndReaderFailuresHold() {
    val pages = sortedPages()
    val finder = LabL1PrefixBounds()
    for (id in listOf(identity.copy(period = "bad"), identity.copy(prize = "other"),
      identity.copy(sourceSha256 = "not-a-sha"))) {
      assertTrue(finder.locate(id, "AB", proof(id)) { pages.getValue(it) }
        is LabL1PrefixBounds.Outcome.Hold)
    }
    assertEquals("L1_PREFIX_ORDER_PROOF_INVALID",
      (finder.locate(identity.copy(period = "115-09-10"), "AB", proof()) {
        pages.getValue(it)
      } as LabL1PrefixBounds.Outcome.Hold).reason)
    assertEquals("L1_PREFIX_READ_FAILURE",
      (finder.locate(identity, "AB", proof()) { error("partial PDF") }
        as LabL1PrefixBounds.Outcome.Hold).reason)
  }
}
