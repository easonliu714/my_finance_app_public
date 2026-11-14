package me.movenext.flutter_pdf_text

/**
 * C28: preserve PDF text extraction order so observed-page monotonicity cannot
 * be bypassed by sorting tokens before the C26/C27 order gate sees them.
 * This does not prove unvisited pages or the global 87K-page order.
 */
internal object PlatformInvoicePageTokenExtractor {
  private val invoicePattern = Regex("[A-Z]\\s*[A-Z](?:\\s*[0-9]){8}")
  private val canonicalPattern = Regex("^[A-Z]{2}[0-9]{8}$")
  private val whitespacePattern = Regex("\\s+")

  fun extractInDocumentOrder(text: String): List<String> {
    val normalized = text.uppercase()
    return invoicePattern.findAll(normalized).mapNotNull { match ->
      val before = normalized.getOrNull(match.range.first - 1)
      val after = normalized.getOrNull(match.range.last + 1)
      if ((before != null && before.isLetterOrDigit()) ||
          (after != null && after.isLetterOrDigit())) {
        null
      } else {
        match.value.replace(whitespacePattern, "")
          .takeIf { canonicalPattern.matches(it) }
      }
    }.toList()
  }
}
