package me.movenext.flutter_pdf_text

/**
 * Lab-only native terminal custody. A complete JSONL batch is not a
 * successful terminal result until PdfRenderer and its descriptors close.
 * A close failure propagates and suppresses the success callback.
 */
internal object LabL1NativeTerminalCustody {
  fun publishAfterClose(
    closeResources: () -> Unit,
    publishSuccess: () -> Unit
  ) {
    closeResources()
    publishSuccess()
  }
}
