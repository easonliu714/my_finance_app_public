package me.movenext.flutter_pdf_text

import java.io.Closeable
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.security.MessageDigest

/**
 * Isolated worker: copy the exact verified bytes to a private, unlinked inode.
 * The PDFium descriptor is duplicated from this inode, never reopened by path.
 * Streaming 64 KiB buffers bound Java heap; insufficient cache space fails closed.
 */
internal object PdfiumWorkerVerifiedSnapshot {
  internal class Snapshot(val file: RandomAccessFile, val bytes: Long, val sha256: String) : Closeable {
    override fun close() = file.close()
  }

  fun open(
    source: File,
    cacheRoot: File,
    expectedBytes: Long,
    expectedSha256: String,
    progress: (Long) -> Unit = {}
  ): Snapshot {
    if (expectedBytes <= 0L || !Regex("^[0-9a-fA-F]{64}$").matches(expectedSha256)) {
      throw IllegalStateException("PDFIUM_WORKER_PROVENANCE_INPUT_INVALID")
    }
    if (!cacheRoot.isDirectory || expectedBytes > Long.MAX_VALUE - 16L * 1024 * 1024 ||
        cacheRoot.usableSpace < expectedBytes + 16L * 1024 * 1024) {
      throw IllegalStateException("PDFIUM_WORKER_SNAPSHOT_DISK_BUDGET_HOLD")
    }
    val temp = File.createTempFile("pdfium-worker-verified-", ".pdf", cacheRoot)
    try {
      val digest = MessageDigest.getInstance("SHA-256")
      var count = 0L
      val buffer = ByteArray(64 * 1024)
      FileInputStream(source).use { input ->
        FileOutputStream(temp).use { output ->
          while (true) {
            val n = input.read(buffer)
            if (n < 0) break
            if (n == 0) continue
            if (n.toLong() > expectedBytes - count) {
              throw IllegalStateException("PDFIUM_WORKER_SOURCE_BYTES_MISMATCH")
            }
            output.write(buffer, 0, n)
            digest.update(buffer, 0, n)
            count += n
            if (count % (8L * 1024 * 1024) < n) progress(count)
          }
          output.flush()
          output.fd.sync()
        }
      }
      progress(count)
      if (count != expectedBytes || temp.length() != expectedBytes) {
        throw IllegalStateException("PDFIUM_WORKER_SOURCE_BYTES_MISMATCH")
      }
      val actual = digest.digest().joinToString("") {
        (it.toInt() and 255).toString(16).padStart(2, '0')
      }
      if (!actual.equals(expectedSha256, ignoreCase = true)) {
        throw IllegalStateException("PDFIUM_WORKER_SOURCE_SHA256_MISMATCH")
      }
      val handle = RandomAccessFile(temp, "r")
      if (!temp.delete()) {
        handle.close()
        throw IllegalStateException("PDFIUM_WORKER_SNAPSHOT_UNLINK_HOLD")
      }
      return Snapshot(handle, count, actual)
    } finally {
      if (temp.exists()) temp.delete()
    }
  }
}
