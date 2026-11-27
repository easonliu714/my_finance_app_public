package me.movenext.flutter_pdf_text

/**
 * One-page diagnostic extraction for the accepted May-June draw-order PDF.
 * Full-10 identifiers only; no complete-source or award-status authority.
 */
internal object LabL1MayJuneDrawPage {
  const val maxTextChars = 250_000
  private const val prefix = "LAB_MAY_JUNE_DRAW_PAGE"
  private val request = Regex("^LAB_MAY_JUNE_DRAW_PAGE:([1-9][0-9]{0,4})$")
  private val token = Regex(
    "(?<![\\p{L}\\p{N}\\p{M}])[A-Z]\\s*[A-Z](?:\\s*[0-9]){8}(?![\\p{L}\\p{N}\\p{M}])"
  )
  private val whitespace = Regex("\\s+")

  fun requestedPage(candidate: String): Int? {
    if (!candidate.startsWith(prefix)) return null
    val page = request.matchEntire(candidate)?.groupValues?.get(1)?.toIntOrNull()
    if (page == null || page !in 1..LabL1MayJuneOwnerAttestedBytePair.expectedPageCount) {
      throw IllegalStateException("L1_OWNER_DRAW_PAGE_INVALID")
    }
    return page
  }

  fun extract(text: String): List<String> {
    if (text.length > maxTextChars) {
      throw IllegalStateException("L1_OWNER_DRAW_TEXT_BUDGET_HOLD")
    }
    val expected = LabL1SortedPageGuard.cloud500TokensPerPage
    val tokens = token.findAll(text).map { it.value.replace(whitespace, "") }
      .take(expected + 1).toList()
    if (tokens.size != expected || tokens.toSet().size != expected) {
      throw IllegalStateException("L1_OWNER_DRAW_PAGE_INCOMPLETE_HOLD")
    }
    // Preserve draw order; sorting would erase independent page evidence.
    return tokens
  }
}
