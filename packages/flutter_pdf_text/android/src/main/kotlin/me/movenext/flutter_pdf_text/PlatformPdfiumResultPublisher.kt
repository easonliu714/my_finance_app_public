package me.movenext.flutter_pdf_text

/**
 * C23: PDFium's native terminal uses the common directory-anchored writer.
 * Strict worker epoch + terminal provenance are required for COMPLETE.
 * This does NOT authenticate a public pathname against a hostile same-UID
 * process, or establish crash-durable consumer acceptance.
 */
internal class PlatformPdfiumResultPublisher(
  private val writer: PlatformResultAtomicWriter = PlatformResultAtomicWriter(
    requireWorkerEpoch = true,
    requireTerminalProvenance = true
  )
) {
  fun publish(path: String, content: String) {
    writer.write(path, content)
  }
}
