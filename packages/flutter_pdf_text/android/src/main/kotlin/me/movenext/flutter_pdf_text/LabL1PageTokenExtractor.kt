package me.movenext.flutter_pdf_text

/**
 * Extracts exact, bounded invoice identifiers from real PDFium page text.
 * Does not attest source SHA, page coverage, or award status.
 */
internal object LabL1PageTokenExtractor {
  // PDFium can emit non-ASCII letters/digits beside ASCII invoice-shaped text.
  // Unicode combining marks are part of the neighboring grapheme, not token
  // separators. PDFium can split a malformed identifier across such a mark.
  // Reject the substring instead of promoting it to an exact Full-10 match.
  private val token = Regex("(?<![\\p{L}\\p{N}\\p{M}])[A-Z]{2}[0-9]{8}(?![\\p{L}\\p{N}\\p{M}])")
  fun extract(text: String): List<String> {
    require(text.length <= 2_000_000) { "L1_PAGE_TEXT_TOO_LARGE_HOLD" }
    val matches = token.findAll(text).map { it.value }.take(100_001).toList()
    require(matches.size <= 100_000) { "L1_PAGE_TOKENS_TOO_MANY_HOLD" }
    return matches
  }
}
