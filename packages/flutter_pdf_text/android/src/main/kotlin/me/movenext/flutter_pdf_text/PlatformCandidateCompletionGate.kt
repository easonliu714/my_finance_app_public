package me.movenext.flutter_pdf_text

/**
 * Bounded search may prove individual positive matches, never a global negative.
 * A terminal COMPLETE is permitted only when every requested candidate has
 * an exact, page-backed positive. Partial/zero matches remain UNKNOWN.
 * This is not result-file authenticity, same-UID isolation or page-order proof.
 */
internal object PlatformCandidateCompletionGate {
  fun allCandidatesPositivelyMatched(
    candidates: Collection<String>,
    matched: Set<String>,
    matchedPages: Map<String, Int>,
    pageCount: Int
  ): Boolean {
    if (pageCount <= 0 || candidates.isEmpty() ||
        candidates.toSet().size != candidates.size ||
        matched.size != candidates.size ||
        matchedPages.size != matched.size) return false
    return candidates.all { candidate ->
      candidate in matched && (matchedPages[candidate] ?: 0) in 1..pageCount
    }
  }
}
