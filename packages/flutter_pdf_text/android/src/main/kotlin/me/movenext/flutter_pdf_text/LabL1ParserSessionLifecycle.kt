package me.movenext.flutter_pdf_text

/**
 * Diagnostic-only lifecycle guard for two parser sessions. A session identifier
 * is NOT byte custody: the caller must separately prove that the parser reads
 * the SHA-verified bytes without reopening a mutable path.
 *
 * This guard deliberately never authorizes OwnerPositiveGate by itself.
 */
internal class LabL1ParserSessionLifecycle {
  internal enum class Role { SORTED, DRAW_ORDER }
  private val active = mutableMapOf<Role, String>()
  private var closed = false

  @Synchronized
  fun register(role: Role, sessionId: String): Boolean {
    if (closed || sessionId.isBlank() || active.containsKey(role) ||
        active.values.contains(sessionId)) return false
    active[role] = sessionId
    return true
  }

  @Synchronized
  fun isActivePair(sortedId: String, drawId: String): Boolean =
    !closed && sortedId != drawId &&
      active[Role.SORTED] == sortedId && active[Role.DRAW_ORDER] == drawId

  @Synchronized
  fun close(role: Role, sessionId: String): Boolean {
    if (closed || active[role] != sessionId) return false
    active.remove(role)
    return true
  }

  @Synchronized
  fun invalidate() {
    closed = true
    active.clear()
  }
}
