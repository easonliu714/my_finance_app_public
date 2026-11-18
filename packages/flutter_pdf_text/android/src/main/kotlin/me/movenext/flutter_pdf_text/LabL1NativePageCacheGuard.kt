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
    val next = (epochs[sessionId] ?: 0L) + 1L
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
    if (epochs[sessionId] != epoch || !liveSessions.contains(sessionId)) false
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
    epochs.remove(sessionId)
    cachedPages.remove(sessionId)
  }

  fun beginRead(sessionId: String, cachedPages: MutableMap<String, Map<String, Any>>) {
    // Do not retain a prior successful probe if the next page is missing,
    // out of range, unreadable, or fails token validation.
    cachedPages.remove(sessionId)
  }
}
