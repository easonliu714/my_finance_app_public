package me.movenext.flutter_pdf_text

import java.io.File
import java.io.FileOutputStream

/**
 * Lab-only durable-result custody for the isolated PDF worker.
 * Never delete a previous result or fall back to an in-place write:
 * a failed replacement must leave the previous complete JSON intact.
 * Android's app-private Linux filesystem provides same-directory rename.
 * This is not evidence of process exit or parent-directory fsync.
 */
internal object LabL1AtomicResultWriter {
  @Synchronized
  fun replace(path: String, payload: String) {
    require(path.isNotBlank()) { "L1_RESULT_PATH_EMPTY" }
    val target = File(path).absoluteFile
    val parent = target.parentFile
      ?: throw IllegalStateException("L1_RESULT_PARENT_MISSING")
    if (!parent.isDirectory && !parent.mkdirs()) {
      throw IllegalStateException("L1_RESULT_PARENT_UNAVAILABLE")
    }
    val pending = File.createTempFile(".${target.name}.", ".part", parent)
    try {
      FileOutputStream(pending).use { output ->
        output.write(payload.toByteArray(Charsets.UTF_8))
        output.flush()
        output.fd.sync()
      }
      if (!pending.renameTo(target)) {
        throw IllegalStateException("L1_RESULT_ATOMIC_RENAME_FAILED")
      }
    } finally {
      if (pending.exists()) pending.delete()
    }
  }
}
