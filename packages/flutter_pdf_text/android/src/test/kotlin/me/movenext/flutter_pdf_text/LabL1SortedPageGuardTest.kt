package me.movenext.flutter_pdf_text

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class LabL1SortedPageGuardTest {
  // These are SYNTHETIC period-scoped fixtures, not official May-June winners.
  private fun page(prefix: String): List<String> =
    (0 until 50).map { "$prefix%08d".format(it) }

  private fun rejects(reason: String, action: () -> Unit) {
    try {
      action()
      fail("Expected $reason")
    } catch (e: IllegalStateException) {
      assertEquals(reason, e.message)
    }
  }

  @Test fun mayJuneAndJulyAugustSyntheticPositiveAndNegativeExactTenCharacters() {
    val sources = mapOf("115-05-06" to page("BA"), "115-07-08" to page("CG"))
    for ((period, fixture) in sources) {
      assertTrue(period.startsWith("115-"))
      val tokens = LabL1SortedPageGuard.extractPage(fixture.joinToString("\n"))
      assertEquals(50, tokens.size)
      assertTrue(tokens.contains(fixture[19]))
      assertFalse(tokens.contains(fixture[19].take(2) + "99999999"))
      assertFalse(tokens.contains("CR00000019"))
      assertFalse(tokens.contains(fixture[19].drop(2)))
    }
    val mayJune = LabL1SortedPageGuard.extractPage(sources.getValue("115-05-06").joinToString("\n"))
    val julyAugust = LabL1SortedPageGuard.extractPage(sources.getValue("115-07-08").joinToString("\n"))
    assertFalse(julyAugust.contains(mayJune[19]))
    assertFalse(mayJune.contains(julyAugust[19]))
  }

  @Test fun extractsWhitespaceSeparatedNumbersAndRejectsPartialCandidates() {
    val spaced = page("BA").map { it.take(2) + " " + it.drop(2).toList().joinToString(" ") }
    val tokens = LabL1SortedPageGuard.extractPage(spaced.joinToString("\n"))
    assertEquals("BA00000000", tokens.first())
    assertEquals("BA00000049", tokens.last())
    assertEquals("BA00000019", LabL1SortedPageGuard.normalizeCandidate("ba00000019"))
    for (invalid in listOf("BA0000001", "BA000000190", "BA 00000019", "00000019", "AB000000XX")) {
      rejects("L1_SEARCH_CANDIDATE_INVALID") { LabL1SortedPageGuard.normalizeCandidate(invalid) }
    }
  }

  @Test fun incompleteAndOverfullPagesHoldInsteadOfReturningFalseNegative() {
    for (fixture in listOf(page("BA").dropLast(1), page("BA") + "BA00000050")) {
      rejects("L1_SEARCH_PAGE_TOKEN_COUNT_MISMATCH") {
        LabL1SortedPageGuard.extractPage(fixture.joinToString("\n"))
      }
    }
  }

  @Test fun duplicatePageTokensHoldBeforeSortOrDeduplication() {
    val fixture = page("BA").toMutableList().also { it[49] = it[0] }
    rejects("L1_SEARCH_PAGE_DUPLICATE_OR_INVALID") {
      LabL1SortedPageGuard.extractPage(fixture.joinToString("\n"))
    }
  }

  @Test fun embeddedExtraCharactersDoNotPassAsCompleteInvoices() {
    val fixture = page("BA").toMutableList().also { it[0] = "X" + it[0] }
    rejects("L1_SEARCH_PAGE_TOKEN_COUNT_MISMATCH") {
      LabL1SortedPageGuard.extractPage(fixture.joinToString("\n"))
    }
  }

  @Test fun invalidPageBudgetFailsClosed() {
    rejects("L1_SEARCH_PAGE_BUDGET_INVALID") {
      LabL1SortedPageGuard.extractPage(page("BA").joinToString("\n"), expectedTokens = 51)
    }
  }
}
