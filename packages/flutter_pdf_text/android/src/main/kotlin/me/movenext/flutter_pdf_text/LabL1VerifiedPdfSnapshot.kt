package me.movenext.flutter_pdf_text

import java.io.Closeable
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.security.MessageDigest

/**
 * Diagnostic-only same-bytes handoff for the May/June Owner-attested pair.
 * Copy into an app-private unlinked snapshot, verify the COMPLETE copied bytes,
 * and return the already-open read-only descriptor for Pdfium duplication.
 * A caller cannot validate one pathname and ask Pdfium to reopen another.
 *
 * The temporary file is unlinked before the descriptor is returned. No public
 * name or writable descriptor is retained. The only admission is a pinned
 * role-specific byte count plus SHA256; this does NOT authorize production
 * Cloud500 WIN/NOT_WIN, publication or posting.
 */
internal object LabL1VerifiedPdfSnapshot {
  internal data class Expected(
    val role: LabL1MayJuneDualPdfOracle.Role,
    val bytes: Long,
    val sha256: String
  )

  internal class Snapshot internal constructor(
    internal val readOnlyFile: RandomAccessFile,
    val role: LabL1MayJuneDualPdfOracle.Role,
    val bytes: Long,
    val sha256: String
  ) : Closeable {
    override fun close() = readOnlyFile.close()
  }

  private const val maxBytes = 200_000_000L
  private const val reserveBytes = 16L * 1024 * 1024

  fun openOwner(
    source: File,
    appFilesRoot: File,
    appCacheRoot: File,
    role: LabL1MayJuneDualPdfOracle.Role
  ): Snapshot {
    val pinned = LabL1MayJuneOwnerAttestedBytePair.pinnedRole(role)
    return openVerified(
      source, appFilesRoot, appCacheRoot, Expected(role, pinned.first, pinned.second))
  }

  /** Isolated fixture seam: synthetic manifests never reach the MethodChannel. */
  internal fun openVerified(
    source: File,
    appFilesRoot: File,
    appCacheRoot: File,
    expected: Expected
  ): Snapshot {
    if (expected.bytes !in 10L..maxBytes ||
        !Regex("[0-9a-f]{64}").matches(expected.sha256)) {
      throw IllegalStateException("L1_SNAPSHOT_EXPECTATION_INVALID")
    }
    val root = appFilesRoot.canonicalFile
    val inputFile = source.canonicalFile
    val cache = appCacheRoot.canonicalFile
    if (!root.isDirectory || !inputFile.path.startsWith(root.path + File.separator) ||
        !inputFile.isFile) {
      throw IllegalStateException("L1_SNAPSHOT_SOURCE_OUTSIDE_APP_FILES")
    }
    if (!cache.isDirectory || cache.usableSpace < expected.bytes + reserveBytes) {
      throw IllegalStateException("L1_SNAPSHOT_DISK_BUDGET_EXCEEDED")
    }
    if (inputFile.length() != expected.bytes) {
      throw IllegalStateException("L1_SNAPSHOT_BYTES_MISMATCH")
    }

    val temp = File.createTempFile("l1-owner-verified-", ".pdf", cache)
    try {
      val buffer = ByteArray(64 * 1024)
      val digest = MessageDigest.getInstance("SHA-256")
      var total = 0L
      FileInputStream(inputFile).use { input ->
        FileOutputStream(temp).use { output ->
          var zeroReads = 0
          while (true) {
            val size = input.read(buffer)
            if (size < 0) break
            if (size == 0) {
              if (++zeroReads > 32) {
                throw IllegalStateException("L1_SNAPSHOT_STREAM_STALLED")
              }
              continue
            }
            zeroReads = 0
            if (size > expected.bytes - total) {
              throw IllegalStateException("L1_SNAPSHOT_BYTES_MISMATCH")
            }
            output.write(buffer, 0, size)
            digest.update(buffer, 0, size)
            total += size
          }
          output.flush()
          output.fd.sync()
        }
      }
      if (total != expected.bytes || temp.length() != expected.bytes) {
        throw IllegalStateException("L1_SNAPSHOT_BYTES_MISMATCH")
      }
      val actual = digest.digest().joinToString("") {
        "%02x".format(it.toInt() and 255)
      }
      if (actual != expected.sha256) {
        throw IllegalStateException("L1_SNAPSHOT_SHA_MISMATCH")
      }
      val opened = RandomAccessFile(temp, "r")
      if (!temp.delete()) {
        opened.close()
        throw IllegalStateException("L1_SNAPSHOT_UNLINK_FAILED")
      }
      // Only an open read-only descriptor survives; no pathname can be reopened.
      return Snapshot(opened, expected.role, total, actual)
    } finally {
      if (temp.exists()) temp.delete()
    }
  }
}
