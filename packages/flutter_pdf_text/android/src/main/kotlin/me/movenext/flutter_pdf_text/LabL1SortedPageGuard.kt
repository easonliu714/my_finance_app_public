package me.movenext.flutter_pdf_text

import java.util.Locale

/**
 * A fail-closed diagnostic guard for each sampled page of a sorted Cloud-500
 * award PDF. It makes no claim about pages that the binary search did not read.
 */
internal object LabL1SortedPageGuard {
  const val cloud500TokensPerPage: Int = 50
  private val completeInvoice = Regex("[A-Z]{2}[0-9]{8}")
  private val embeddedAwareCapture = Regex(
    "(?<![A-Z0-9])[A-Z]\\s*[A-Z](?:\\s*[0-9]){8}(?![A-Z0-9])"
  )
  private val whitespace = Regex("\\s+")

  fun normalizeCandidate(raw: String): String {
    val candidate = raw.trim().uppercase(Locale.ROOT)
    if (!completeInvoice.matches(candidate)) {
      throw IllegalStateException("L1_SEARCH_CANDIDATE_INVALID")
    }
    return candidate
  }

  fun extractPage(text: String, expectedTokens: Int = cloud500TokensPerPage): List<String> {
    if (expectedTokens !in 1..cloud500TokensPerPage) {
      throw IllegalStateException("L1_SEARCH_PAGE_BUDGET_INVALID")
    }
    val tokens = embeddedAwareCapture.findAll(text.uppercase(Locale.ROOT))
      .map { it.value.replace(whitespace, "") }
      .toList()
    if (tokens.size != expectedTokens) {
      throw IllegalStateException("L1_SEARCH_PAGE_TOKEN_COUNT_MISMATCH")
    }
    if (tokens.any { !completeInvoice.matches(it) } || tokens.toSet().size != expectedTokens) {
      throw IllegalStateException("L1_SEARCH_PAGE_DUPLICATE_OR_INVALID")
    }
    return tokens.sorted()
  }
}
