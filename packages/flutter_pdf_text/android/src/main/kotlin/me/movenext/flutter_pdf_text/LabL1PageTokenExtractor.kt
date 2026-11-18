package me.movenext.flutter_pdf_text

/**
 * Extracts exact, bounded invoice identifiers from real PDFium page text.
 * Does not attest source SHA, page coverage, or award status.
 */
internal object LabL1PageTokenExtractor {
  // PDFium can emit non-ASCII letters/digits beside ASCII invoice-shaped text.
  // ASCII-only boundaries would incorrectly turn a substring into a Full-10 token.
  private val token = Regex("(?<![\\p{L}\\p{N}])[A-Z]{2}[0-9]{8}(?![\\p{L}\\p{N}])")
  fun extract(text: String): List<String> {
    require(text.length <= 2_000_000) { "L1_PAGE_TEXT_TOO_LARGE_HOLD" }
    val matches = token.findAll(text).map { it.value }.take(100_001).toList()
    require(matches.size <= 100_000) { "L1_PAGE_TOKENS_TOO_MANY_HOLD" }
    return matches
  }
}
