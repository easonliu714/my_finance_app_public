package me.movenext.flutter_pdf_text

import java.util.TreeMap

/**
 * C27: sampled sorted-page consistency guard for bounded candidate searches.
 * An inversion among visited page bounds fails closed. Re-reading a page must
 * reproduce every token, not merely its first/last bounds. Unseen pages are
 * NOT certified monotonic. This is neither a global-negative proof nor a source
 * identity, result authenticity, or same-UID hostile-write defense.
 */
internal class PlatformObservedPageOrderGate(private val pageCount: Int) {
  private val observed = TreeMap<Int, List<String>>()

  fun observe(pageNumber: Int, tokens: List<String>): Boolean {
    if (pageCount <= 0 || pageNumber !in 1..pageCount || tokens.isEmpty() ||
        tokens.zipWithNext().any { (left, right) -> left > right }) return false
    // C27: a same-page reread with changed interior tokens must fail closed.
    // PDFium may reopen a page for each candidate; equal bounds alone cannot
    // establish that the exact candidate universe was searched consistently.
    observed[pageNumber]?.let { return it == tokens }
    val lower = observed.lowerEntry(pageNumber)
    val upper = observed.higherEntry(pageNumber)
    if (lower != null && lower.value.last() > tokens.first()) return false
    if (upper != null && tokens.last() > upper.value.first()) return false
    // Snapshot the full token list: the extractor may reuse a mutable list.
    observed[pageNumber] = tokens.toList()
    return true
  }
}
