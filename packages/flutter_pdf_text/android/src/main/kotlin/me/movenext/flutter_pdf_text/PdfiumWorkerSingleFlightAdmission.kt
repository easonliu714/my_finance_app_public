package me.movenext.flutter_pdf_text

import java.util.concurrent.atomic.AtomicReference

/**
 * A PDFium worker can hold a >100MB official source and a large native heap.
 * Reject overlapping work rather than allocating a second native document in
 * the same process or letting an earlier job stop a newer one.
 *
 * No invoice numbers or source paths are persisted by this admission guard.
 */
internal class PdfiumWorkerSingleFlightAdmission {
  private data class Owner(val requestId: String, val resultPath: String)
  private val owner = AtomicReference<Owner?>(null)

  fun tryStart(requestId: String, resultPath: String): Boolean {
    if (requestId.isBlank() || resultPath.isBlank()) return false
    return owner.compareAndSet(null, Owner(requestId, resultPath))
  }

  fun finish(requestId: String): Boolean {
    val current = owner.get() ?: return false
    return current.requestId == requestId && owner.compareAndSet(current, null)
  }

  fun isActive(): Boolean = owner.get() != null
  fun isActivePath(resultPath: String): Boolean = owner.get()?.resultPath == resultPath
}
