package me.movenext.flutter_pdf_text

/**
 * Diagnostic-only PDFium page admission. Keep all potentially throwing
 * epoch and native page-count operations inside a result-returning boundary.
 * No positive tokens, award status, or formal ledger writes are produced here.
 */
internal object LabL1NativePageReadAdmission {
  sealed class Outcome<out T> {
    data class Ready<T : Any>(
      val document: T,
      val pageCount: Int,
      val epoch: Long?
    ) : Outcome<T>()
    data class Hold(val code: String, val retire: Boolean) : Outcome<Nothing>()
  }

  fun <T : Any> admit(
    sessionId: String,
    pageNumber: Int,
    structuredTokens: Boolean,
    verifiedRole: Boolean,
    documents: Map<String, T>,
    cachedPages: MutableMap<String, Map<String, Any>>,
    epochs: MutableMap<String, Long>,
    getPageCount: (T) -> Int
  ): Outcome<T> {
    // Invalidate an earlier positive before checking missing or invalid pages.
    val epoch = try {
      LabL1NativePageCacheGuard.beginPageRequest(
        sessionId, structuredTokens, verifiedRole, cachedPages, epochs
      )
    } catch (_: OutOfMemoryError) {
      return Outcome.Hold("PDFIUM_PAGE_OOM", retire = verifiedRole)
    } catch (_: Exception) {
      // Exhausted/invalid epoch is not a silently dropped MethodChannel reply.
      return Outcome.Hold("L1_PAGE_READ_EPOCH_HOLD", retire = verifiedRole)
    }

    val document = documents[sessionId]
      ?: return Outcome.Hold("PDFIUM_SESSION_NOT_FOUND", retire = false)
    val count = try {
      getPageCount(document)
    } catch (_: OutOfMemoryError) {
      return Outcome.Hold("PDFIUM_PAGE_OOM", retire = verifiedRole)
    } catch (_: Exception) {
      return Outcome.Hold("PDFIUM_PAGE_COUNT_FAILED", retire = verifiedRole)
    }
    if (count <= 0) {
      return Outcome.Hold("PDFIUM_PAGE_COUNT_INVALID", retire = verifiedRole)
    }
    if (pageNumber < 1 || pageNumber > count) {
      return Outcome.Hold("PDFIUM_PAGE_OUT_OF_RANGE", retire = false)
    }
    return Outcome.Ready(document, count, epoch)
  }
}
