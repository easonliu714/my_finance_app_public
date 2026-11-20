package me.movenext.flutter_pdf_text

/** Fail-closed cache transition for native role-bound PDFium page reads. */
internal object LabL1NativePageCacheGuard {
  // An older, slower PDFium read must never repopulate a cache after a newer read.
  // Epochs are per session; all transitions are guarded by the same monitor.
  fun beginVersionedRead(
    sessionId: String,
    cachedPages: MutableMap<String, Map<String, Any>>,
    epochs: MutableMap<String, Long>
  ): Long = synchronized(epochs) {
    val prior = epochs[sessionId] ?: 0L
    // Never wrap to an epoch that a stale read may still hold.
    // Reserve MAX_VALUE for retirement: issuing it permits stale publication after retire.\n    check(prior >= 0L && prior < Long.MAX_VALUE - 1L) { "L1_SESSION_EPOCH_EXHAUSTED" }
    val next = prior + 1L
    epochs[sessionId] = next
    cachedPages.remove(sessionId)
    next
  }

  fun publishIfCurrent(
    sessionId: String,
    epoch: Long,
    page: Map<String, Any>,
    cachedPages: MutableMap<String, Map<String, Any>>,
    epochs: MutableMap<String, Long>,
    liveSessions: Set<String>
  ): Boolean = synchronized(epochs) {
    if (epoch <= 0L || epoch == Long.MAX_VALUE || epochs[sessionId] != epoch || !liveSessions.contains(sessionId)) false
    else {
      cachedPages[sessionId] = page
      true
    }
  }

  fun retire(
    sessionId: String,
    cachedPages: MutableMap<String, Map<String, Any>>,
    epochs: MutableMap<String, Long>
  ) = synchronized(epochs) {
    // Retain a tombstone until plugin detach so a reopened ID cannot replay
    // a previously issued epoch. Exhaustion remains fail closed.
    val prior = epochs[sessionId]
    epochs[sessionId] = if (prior == null || prior >= Long.MAX_VALUE - 1L) Long.MAX_VALUE else prior + 1L
    cachedPages.remove(sessionId)
  }

  fun beginRead(sessionId: String, cachedPages: MutableMap<String, Map<String, Any>>) {
    // Do not retain a prior successful probe if the next page is missing,
    // out of range, unreadable, or fails token validation.
    cachedPages.remove(sessionId)
  }
}
