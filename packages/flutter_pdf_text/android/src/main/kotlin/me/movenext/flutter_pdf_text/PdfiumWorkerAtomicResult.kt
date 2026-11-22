package me.movenext.flutter_pdf_text

import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * Publishes worker progress/results only through a completed sibling rename.
 * A failed rename must leave the previously published JSON byte-for-byte intact.
 * Unique sibling temps avoid collisions between heartbeat and failure writers.
 */
internal object PdfiumWorkerAtomicResult {
  fun write(
    target: File,
    content: String,
    rename: (File, File) -> Boolean = { source, destination -> source.renameTo(destination) }
  ) {
    val parent = target.absoluteFile.parentFile
      ?: throw IOException("PDFIUM_WORKER_RESULT_PARENT_MISSING")
    if (!parent.isDirectory && !parent.mkdirs()) {
      throw IOException("PDFIUM_WORKER_RESULT_PARENT_MISSING")
    }
    val temp = File.createTempFile(target.name + ".", ".pending", parent)
    try {
      FileOutputStream(temp).use { output ->
        output.write(content.toByteArray(Charsets.UTF_8))
        output.fd.sync()
      }
      if (!rename(temp, target)) {
        throw IOException("PDFIUM_WORKER_RESULT_ATOMIC_RENAME_FAILED")
      }
    } finally {
      if (temp.exists()) temp.delete()
    }
  }
}
