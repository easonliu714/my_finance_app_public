package me.movenext.flutter_pdf_text

/**
 * Fail-closed foreground ownership for one Android Service instance.
 * This now retains an OS-held file lock; durable terminal identity and\n * Android process-death recovery are still unverified.
 */
internal class PlatformWorkerStartLease(
  private val acquireProcessLease: (String) -> java.io.Closeable? = {
    PlatformResultProcessLease.tryAcquire(it)
  }
) {
  class Token internal constructor(
    val startId: Int,
    val requestId: String,
    val resultPath: String,
    internal val processLease: java.io.Closeable
  )

  private var active: Token? = null
  private var closing = false

  @Synchronized
  fun acquire(startId: Int, requestId: String, resultPath: String): Token? {
    if (closing || active != null || startId <= 0 ||
        requestId.isBlank() || resultPath.isBlank()) return null
    // An unavailable OS-held lock is UNKNOWN: never start a second writer.
    val processLease = try { acquireProcessLease(resultPath) }
      catch (_: Exception) { null } ?: return null
    return Token(startId, requestId, resultPath, processLease)
      .also { active = it }
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
      try { token.processLease.close() } finally { active = null }
    }
    return true
  }
}
