package me.movenext.flutter_pdf_text

/** Fail-closed cache transition for native role-bound PDFium page reads. */
internal object LabL1NativePageCacheGuard {
  fun beginRead(sessionId: String, cachedPages: MutableMap<String, Map<String, Any>>) {
    // Do not retain a prior successful probe if the next page is missing,
    // out of range, unreadable, or fails token validation.
    cachedPages.remove(sessionId)
  }
}
