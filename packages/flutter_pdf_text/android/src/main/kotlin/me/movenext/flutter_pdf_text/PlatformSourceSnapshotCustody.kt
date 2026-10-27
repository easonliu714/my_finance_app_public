package me.movenext.flutter_pdf_text

import android.os.ParcelFileDescriptor
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.StandardOpenOption
import java.security.MessageDigest

/**
 * Copies a single no-follow source FD into a private, unique, fsynced snapshot.
 * Both verification and PdfRenderer read the same unlinked snapshot inode,
 * never a second open of the caller-controlled source pathname.
 *
 * This closes pathname-swap TOCTOU, not process-death, external FD writers,
 * durable terminal identity or global-negative-completeness proof.
 */
internal object PlatformSourceSnapshotCustody {
  data class VerifiedSource(
    val descriptor: ParcelFileDescriptor,
    val sha256: String,
    val bytes: Long
  )

  fun capture(
    source: File,
    privateDirectory: File,
    expectedBytes: Long,
    expectedSha256: String,
    onProgress: (Long) -> Unit = {}
  ): VerifiedSource {
    if (expectedBytes <= 0L || !Regex("^[0-9a-fA-F]{64}$").matches(expectedSha256)) {
      throw IOException("SOURCE_CUSTODY_EXPECTATION_INVALID")
    }
    val original = source.toPath()
    val directory = privateDirectory.toPath()
    if (!Files.isRegularFile(original, LinkOption.NOFOLLOW_LINKS) ||
        !Files.isDirectory(directory, LinkOption.NOFOLLOW_LINKS)) {
      throw IOException("SOURCE_CUSTODY_PATH_UNTRUSTED")
    }

    // App-private cache, not a result directory or the mutable original path.
    val snapshot = Files.createTempFile(directory, ".platform-source-custody-", ".pdf")
    var renderFd: ParcelFileDescriptor? = null
    try {
      FileChannel.open(original, StandardOpenOption.READ, LinkOption.NOFOLLOW_LINKS).use { input ->
        FileChannel.open(snapshot, StandardOpenOption.WRITE, LinkOption.NOFOLLOW_LINKS).use { output ->
          val buffer = ByteBuffer.allocate(64 * 1024)
          var copied = 0L
          var nextProgress = 8L * 1024L * 1024L
          while (true) {
            buffer.clear()
            val read = input.read(buffer)
            if (read < 0) break
            if (read == 0) continue
            copied += read
            if (copied > expectedBytes) throw IOException("SOURCE_CUSTODY_BYTES_EXCEEDED")
            buffer.flip()
            while (buffer.hasRemaining()) output.write(buffer)
            if (copied >= nextProgress) {
              onProgress(copied)
              nextProgress = copied + 8L * 1024L * 1024L
            }
          }
          if (copied != expectedBytes) throw IOException("SOURCE_CUSTODY_BYTES_MISMATCH")
          output.force(true)
        }
      }

      // Independent read offsets, same snapshot inode. Unlink before hashing:
      // no later pathname swap can redirect the descriptor passed to PdfRenderer.
      renderFd = ParcelFileDescriptor.open(snapshot.toFile(), ParcelFileDescriptor.MODE_READ_ONLY)
      ParcelFileDescriptor.open(snapshot.toFile(), ParcelFileDescriptor.MODE_READ_ONLY).use { hashFd ->
        Files.delete(snapshot)
        val digest = MessageDigest.getInstance("SHA-256")
        var total = 0L
        val buffer = ByteArray(64 * 1024)
        ParcelFileDescriptor.AutoCloseInputStream(hashFd).use { input ->
          while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            if (read == 0) continue
            total += read
            if (total > expectedBytes) throw IOException("SOURCE_CUSTODY_VERIFIED_BYTES_EXCEEDED")
            digest.update(buffer, 0, read)
          }
        }
        if (total != expectedBytes) throw IOException("SOURCE_CUSTODY_VERIFIED_BYTES_MISMATCH")
        val actualSha = digest.digest().joinToString("") {
          (it.toInt() and 0xff).toString(16).padStart(2, '0')
        }
        if (!actualSha.equals(expectedSha256, ignoreCase = true)) {
          throw IOException("SOURCE_CUSTODY_SHA256_MISMATCH")
        }
        onProgress(total)
        val verified = VerifiedSource(renderFd ?: throw IOException("SOURCE_CUSTODY_DESCRIPTOR_MISSING"), actualSha, total)
        renderFd = null
        return verified
      }
    } finally {
      try { renderFd?.close() } catch (_: Exception) {}
      Files.deleteIfExists(snapshot)
    }
  }
}
