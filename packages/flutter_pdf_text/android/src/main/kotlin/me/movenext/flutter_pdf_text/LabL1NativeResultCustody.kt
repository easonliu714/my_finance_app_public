package me.movenext.flutter_pdf_text

/**
 * Per-worker result-state fence for the isolated Lab PDF probe.
 * Serialize heartbeat and terminal writes through the atomic result writer.
 * Once a terminal JSON is successfully persisted, a late heartbeat or a
 * second terminal snapshot from this worker must not replace it.
 * This does not prove native process exit or parent-directory fsync.
 */
internal class LabL1NativeResultCustody {
  private var terminalPublished = false

  @Synchronized
  fun publish(path: String, status: String, payload: String): Boolean {
    require(status == "running" || status == "complete" || status == "failure") {
      "L1_RESULT_STATUS_INVALID"
    }
    if (path.isBlank() || terminalPublished) return false
    LabL1AtomicResultWriter.replace(path, payload)
    if (status != "running") terminalPublished = true
    return true
  }
}
