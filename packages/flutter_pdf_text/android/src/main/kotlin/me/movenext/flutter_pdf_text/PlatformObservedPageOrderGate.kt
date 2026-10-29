package me.movenext.flutter_pdf_text

import java.util.TreeMap

/**
 * C26: sampled sorted-page consistency guard for bounded candidate searches.
 * An inversion among visited page bounds fails closed; unseen pages are NOT
 * certified monotonic. This is neither a global-negative proof nor a source
 * identity, result authenticity, or same-UID hostile-write defense.
 */
internal class PlatformObservedPageOrderGate(private val pageCount: Int) {
  private val observed = TreeMap<Int, Pair<String, String>>()

  fun observe(pageNumber: Int, tokens: List<String>): Boolean {
    if (pageCount <= 0 || pageNumber !in 1..pageCount || tokens.isEmpty() ||
        tokens.zipWithNext().any { (left, right) -> left > right }) return false
    val bounds = tokens.first() to tokens.last()
    observed[pageNumber]?.let { return it == bounds }
    val lower = observed.lowerEntry(pageNumber)
    val upper = observed.higherEntry(pageNumber)
    if (lower != null && lower.value.second > bounds.first) return false
    if (upper != null && bounds.second > upper.value.first) return false
    observed[pageNumber] = bounds
    return true
  }
}
