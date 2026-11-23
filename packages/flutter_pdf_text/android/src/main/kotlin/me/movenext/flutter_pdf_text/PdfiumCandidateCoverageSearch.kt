package me.movenext.flutter_pdf_text

/**
 * Native PDFium worker's candidate search contract, free of Android objects
 * for deterministic JVM regression testing.
 *
 * Binary page pivots are ONLY positive hints unless global ordering has been
 * proven independently. A miss starts one streaming pass over EVERY page.
 * This is not an independent official absence/NOT_WIN authority.
 */
internal object PdfiumCandidateCoverageSearch {
  data class Outcome(
    val matchedPages: Map<String, Int>,
    val unresolved: Set<String>,
    val fullCoverageScan: Boolean,
    val positiveFallbackUsed: Boolean = false
  )

  private val full10 = Regex("[A-Z]{2}[0-9]{8}")

  fun search(
    candidates: List<String>,
    pageCount: Int,
    readPage: (pageNumber: Int, candidateIndex: Int, fullCoverage: Boolean) -> List<String>
  ): Outcome {
    require(pageCount > 0 && candidates.isNotEmpty()) { "PDFIUM_SEARCH_SCOPE_INVALID" }
    require(candidates.size == candidates.toSet().size &&
      candidates.all { full10.matches(it) }) { "PDFIUM_SEARCH_CANDIDATES_INVALID" }

    fun read(page: Int, index: Int, full: Boolean): List<String> {
      check(page in 1..pageCount) { "PDFIUM_PAGE_OUT_OF_RANGE" }
      val tokens = readPage(page, index, full)
      // A blank or invalid native extraction cannot certify a covered page.
      check(tokens.isNotEmpty() && tokens.all { full10.matches(it) }) {
        "PDFIUM_COVERAGE_PAGE_UNREADABLE_HOLD"
      }
      return tokens
    }

    val matched = linkedMapOf<String, Int>()
    candidates.forEachIndexed { index, candidate ->
      var low = 1
      var high = pageCount
      var found = false
      while (low <= high) {
        val middle = low + ((high - low) ushr 1)
        val tokens = read(middle, index + 1, false)
        when {
          candidate < tokens.first() -> high = middle - 1
          candidate > tokens.last() -> low = middle + 1
          else -> {
            if (candidate in tokens) {
              matched[candidate] = middle
              found = true
            } else {
              listOf(middle - 1, middle + 1)
                .filter { it in 1..pageCount }
                .forEach { neighbor ->
                  if (!found && candidate in read(neighbor, index + 1, false)) {
                    matched[candidate] = neighbor
                    found = true
                  }
                }
            }
            break
          }
        }
      }
      if (!found && low > high) {
        setOf(low, high).filter { it in 1..pageCount }.forEach { boundary ->
          if (!found && candidate in read(boundary, index + 1, false)) {
            matched[candidate] = boundary
            found = true
          }
        }
      }
    }

    val unresolved = candidates.filterNot { matched.containsKey(it) }.toMutableSet()
    if (unresolved.isEmpty()) return Outcome(matched, emptySet(), false)

    // One pass for ALL unresolved candidates (not one 77k-page pass per
    // candidate). Retain only candidate->page mappings: bounded heap usage.
    for (page in 1..pageCount) {
      val tokens = read(page, candidates.size, true)
      for (token in tokens) {
        if (unresolved.remove(token)) matched[token] = page
      }
      // Once every requested token is positively established, reading the
      // unrelated tail risks native OOM/page errors without adding authority.
      // A truncated positive fallback must NOT report full page coverage.
      if (unresolved.isEmpty()) {
        return Outcome(matched, emptySet(), page == pageCount, true)
      }
    }
    return Outcome(matched, unresolved, true, true)
  }
}
