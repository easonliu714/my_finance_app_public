package me.movenext.flutter_pdf_text

/**
 * Serializes heartbeat and terminal result publication for one admitted worker.
 * Atomic file replacement protects bytes, but does not prevent an older heartbeat
 * from replacing a complete/failed result after the terminal rename.
 */
internal class PdfiumWorkerResultPublication(
  private val writer: (String) -> Unit
) {
  private var terminal = false

  @Synchronized fun publishRunning(json: String): Boolean {
    if (terminal) return false
    writer(json)
    return true
  }

  @Synchronized fun publishTerminal(json: String): Boolean {
    if (terminal) return false
    writer(json)
    // A failed rename must not mark a result as published.
    terminal = true
    return true
  }

  @Synchronized fun reset() {
    terminal = false
  }
}
