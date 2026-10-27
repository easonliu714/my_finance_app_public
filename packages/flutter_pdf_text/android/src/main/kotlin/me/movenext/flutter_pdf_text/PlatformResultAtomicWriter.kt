package me.movenext.flutter_pdf_text

import android.system.Os
import android.system.OsConstants
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.LinkOption
import java.nio.file.StandardCopyOption

/**
 * Process-local serialized native result replacement. Not a cross-process
 * lease or full request/PID/source identity authority. Default production
 * publishing rejects any overwrite of an existing COMPLETE/FAILED result,
 * malformed prior state or foreign-request RUNNING state. Directory-fsync
 * failure after move remains ambiguous, never verified durable COMPLETE.
 */
internal class PlatformResultAtomicWriter(
  private val atomicReplace: (Path, Path) -> Unit = { temp, target ->
    Files.move(temp, target,
      StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
  },
  private val syncParent: (Path) -> Unit = { directory ->
    val fd = Os.open(directory.toString(),
      OsConstants.O_RDONLY, 0)
    try { Os.fsync(fd) } finally { Os.close(fd) }
  },
  private val protectTerminal: Boolean = true
) {
  private fun validateResultTransition(target: Path, incomingContent: String) {
    // The OS-held per-result lease belongs to the calling worker. This
    // guard adds monotonic terminal status, not a replacement for that lease.
    val incoming = try { JSONObject(incomingContent) }
      catch (error: Exception) { throw IOException("RESULT_INCOMING_JSON_INVALID", error) }
    val nextStatus = incoming.optString("status")
    val nextRequest = incoming.optString("request_id")
    if (nextRequest.isBlank() ||
        nextStatus !in setOf("running", "complete", "failed")) {
      throw IOException("RESULT_INCOMING_IDENTITY_INVALID")
    }
    if (!Files.exists(target, LinkOption.NOFOLLOW_LINKS)) return
    if (!Files.isRegularFile(target, LinkOption.NOFOLLOW_LINKS) ||
        Files.size(target) > 1_048_576L) {
      throw IOException("RESULT_PRIOR_FILE_UNTRUSTED")
    }
    val prior = try { JSONObject(Files.readString(target)) }
      catch (error: Exception) { throw IOException("RESULT_PRIOR_JSON_INVALID", error) }
    val oldStatus = prior.optString("status")
    if (oldStatus == "complete" || oldStatus == "failed") {
      throw IOException("RESULT_TERMINAL_IMMUTABLE")
    }
    if (oldStatus != "running") throw IOException("RESULT_PRIOR_STATE_UNKNOWN")
    if (prior.optString("request_id") != nextRequest) {
      throw IOException("RESULT_REQUEST_ID_MISMATCH")
    }
  }

  @Synchronized
  fun write(path: String, content: String) {
    val target = File(path).absoluteFile.toPath()
    val parent = target.parent ?: throw IOException("RESULT_PARENT_MISSING")
    Files.createDirectories(parent)
    if (protectTerminal) validateResultTransition(target, content)
    // Unique temporary file in the same directory, not a shared .tmp path.
    val temp = Files.createTempFile(parent, ".${target.fileName}.", ".tmp")
    try {
      FileOutputStream(temp.toFile()).use { output ->
        output.write(content.toByteArray(Charsets.UTF_8))
        output.fd.sync()
      }
      atomicReplace(temp, target)
      syncParent(parent)
    } finally {
      Files.deleteIfExists(temp)
    }
  }
}
