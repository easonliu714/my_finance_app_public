package me.movenext.flutter_pdf_text

/**
 * Fail-closed foreground ownership for one Android Service instance.
 * This is not a cross-process lock or a durable terminal-result lease.
 */
internal class PlatformWorkerStartLease {
  class Token internal constructor(
    val startId: Int,
    val requestId: String,
    val resultPath: String
  )

  private var active: Token? = null
  private var closing = false

  @Synchronized
  fun acquire(startId: Int, requestId: String, resultPath: String): Token? {
    if (closing || active != null || startId <= 0 ||
        requestId.isBlank() || resultPath.isBlank()) return null
    return Token(startId, requestId, resultPath).also { active = it }
  }

  @Synchronized
  fun isActive(): Boolean = active != null

  /** Cleanup runs under the same monitor as acquire, then permanently closes
   * this instance. A stale startId/requestId cannot release a newer owner.
   */
  @Synchronized
  fun finish(token: Token, cleanup: () -> Unit): Boolean {
    if (closing || active !== token) return false
    closing = true
    try {
      cleanup()
    } finally {
      active = null
    }
    return true
  }
}
