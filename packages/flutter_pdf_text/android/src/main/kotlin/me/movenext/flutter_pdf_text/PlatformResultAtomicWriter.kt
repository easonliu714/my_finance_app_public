package me.movenext.flutter_pdf_text

import android.system.Os
import android.system.OsConstants
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.LinkOption
import java.nio.file.NoSuchFileException
import java.nio.file.OpenOption
import java.nio.file.SecureDirectoryStream
import java.nio.file.StandardOpenOption
import java.util.UUID

/**
 * Process-local serialized native result replacement. Not a cross-process
 * lease or full request/PID/source identity authority. Default production
 * publishing rejects any overwrite of an existing COMPLETE/FAILED result,
 * malformed prior state or foreign-request RUNNING state. In strict production
 * mode, a RUNNING transition also pins PID and per-process random epoch;
 * this is not a cryptographic or same-UID replacement defense. Directory-fsync
 * failure after move remains ambiguous, never verified durable COMPLETE.
 */
internal class PlatformResultAtomicWriter(
  // A non-null replacement is only used by deterministic fault-injection
  // tests. Production always uses the already-open directory FD anchor.
  private val atomicReplace: ((Path, Path) -> Unit)? = null,
  internal val beforeAnchoredMoveForTest: ((Path, Path) -> Unit)? = null,
  private val syncParent: (Path) -> Unit = { directory ->
    val fd = Os.open(directory.toString(),
      OsConstants.O_RDONLY, 0)
    try { Os.fsync(fd) } finally { Os.close(fd) }
  },
  private val protectTerminal: Boolean = true,
  private val requireWorkerEpoch: Boolean = false,
  private val requireTerminalProvenance: Boolean = false
) {
  private val sha256Pattern = Regex("^[0-9a-fA-F]{64}$")
  private val workerEpochPattern =
    Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")

  private fun workerIdentity(payload: JSONObject): Pair<Long, String> {
    val pid = when (val value = payload.opt("worker_pid")) {
      is Int -> value.toLong()
      is Long -> value
      else -> throw IOException("RESULT_WORKER_IDENTITY_INVALID")
    }
    val epoch = payload.optString("worker_epoch")
    if (pid <= 0L || pid > Int.MAX_VALUE.toLong() ||
        !workerEpochPattern.matches(epoch)) {
      throw IOException("RESULT_WORKER_IDENTITY_INVALID")
    }
    return pid to epoch
  }

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
    val incomingWorkerIdentity =
      if (requireWorkerEpoch) workerIdentity(incoming) else null
    // A COMPLETE must carry verified digest syntax and follow a RUNNING state.
    // Matching those digests to RUNNING/source custody is a separate HOLD.
    if (requireTerminalProvenance && nextStatus == "complete" &&
        (!sha256Pattern.matches(incoming.optString("source_sha256")) ||
         !sha256Pattern.matches(incoming.optString("candidate_universe_sha256")))) {
      throw IOException("RESULT_TERMINAL_PROVENANCE_INVALID")
    }
    if (!Files.exists(target, LinkOption.NOFOLLOW_LINKS)) {
      if (requireTerminalProvenance && nextStatus == "complete") {
        throw IOException("RESULT_COMPLETION_WITHOUT_RUNNING")
      }
      return
    }
    if (!Files.isRegularFile(target, LinkOption.NOFOLLOW_LINKS) ||
        Files.size(target) > 1_048_576L) {
      throw IOException("RESULT_PRIOR_FILE_UNTRUSTED")
    }
    val prior = try { JSONObject(String(Files.readAllBytes(target), Charsets.UTF_8)) }
      catch (error: Exception) { throw IOException("RESULT_PRIOR_JSON_INVALID", error) }
    val oldStatus = prior.optString("status")
    if (oldStatus == "complete" || oldStatus == "failed") {
      throw IOException("RESULT_TERMINAL_IMMUTABLE")
    }
    if (oldStatus != "running") throw IOException("RESULT_PRIOR_STATE_UNKNOWN")
    if (prior.optString("request_id") != nextRequest) {
      throw IOException("RESULT_REQUEST_ID_MISMATCH")
    }
    if (incomingWorkerIdentity != null &&
        workerIdentity(prior) != incomingWorkerIdentity) {
      throw IOException("RESULT_WORKER_IDENTITY_MISMATCH")
    }
  }

  // Bounded post-move readback: detect a replaced temporary inode before
  // reporting write() success. This is detection, NOT a same-UID race closure:
  // a forged target may already be visible and directory durability is unknown.
  private fun verifyPublishedBytes(target: Path, expected: ByteArray) {
    if (!Files.isRegularFile(target, LinkOption.NOFOLLOW_LINKS)) {
      throw IOException("RESULT_PUBLICATION_CONTENT_MISMATCH")
    }
    try {
      Files.newInputStream(target, LinkOption.NOFOLLOW_LINKS).use { input ->
        val chunk = ByteArray(8192)
        var offset = 0
        while (offset < expected.size) {
          val count = input.read(chunk, 0, minOf(chunk.size, expected.size - offset))
          if (count <= 0) throw IOException("RESULT_PUBLICATION_CONTENT_MISMATCH")
          for (index in 0 until count) {
            if (chunk[index] != expected[offset + index]) {
              throw IOException("RESULT_PUBLICATION_CONTENT_MISMATCH")
            }
          }
          offset += count
        }
        if (input.read() != -1) throw IOException("RESULT_PUBLICATION_CONTENT_MISMATCH")
      }
    } catch (error: IOException) {
      if (error.message == "RESULT_PUBLICATION_CONTENT_MISMATCH") throw error
      throw IOException("RESULT_PUBLICATION_READBACK_FAILED", error)
    }
  }

  @Synchronized
  fun write(path: String, content: String) {
    val target = File(path).absoluteFile.toPath()
    val parent = target.parent ?: throw IOException("RESULT_PARENT_MISSING")
    // A caller-controlled symlinked result parent must never redirect writes
    // or create the temporary file outside the intended result directory.
    if (Files.exists(parent, LinkOption.NOFOLLOW_LINKS) &&
        !Files.isDirectory(parent, LinkOption.NOFOLLOW_LINKS)) {
      throw IOException("RESULT_PARENT_UNTRUSTED")
    }
    Files.createDirectories(parent)
    if (!Files.isDirectory(parent, LinkOption.NOFOLLOW_LINKS)) {
      throw IOException("RESULT_PARENT_UNTRUSTED")
    }
    if (protectTerminal) validateResultTransition(target, content)
    val expectedBytes = content.toByteArray(Charsets.UTF_8)
    // C20: keep one directory FD anchor from temp creation through rename.
    // A parent pathname replacement must not redirect our own publication
    // into the new directory. This does NOT authenticate arbitrary same-UID
    // writes to the public pathname or make parent fsync durable after swap.
    Files.newDirectoryStream(parent).use { directory ->
      if (directory !is SecureDirectoryStream<*>) {
        throw IOException("RESULT_ANCHORED_DIRECTORY_UNAVAILABLE")
      }
      @Suppress("UNCHECKED_CAST")
      val anchored = directory as SecureDirectoryStream<Path>
      val tempName = parent.fileSystem.getPath(
        ".${target.fileName}.${UUID.randomUUID()}.tmp")
      val temp = parent.resolve(tempName)
      var created = false
      try {
        // Relative openat(CREATE_NEW|NOFOLLOW) on the same held directory.
        // Do not reopen the temporary pathname through a swapped parent.
        anchored.newByteChannel(tempName, setOf<OpenOption>(
          StandardOpenOption.CREATE_NEW,
          StandardOpenOption.WRITE,
          LinkOption.NOFOLLOW_LINKS
        )).use { channel ->
          created = true
          val durable = channel as? FileChannel
            ?: throw IOException("RESULT_TEMP_FSYNC_UNAVAILABLE")
          val buffer = ByteBuffer.wrap(expectedBytes)
          while (buffer.hasRemaining()) durable.write(buffer)
          durable.force(true)
        }
        if (atomicReplace != null) {
          atomicReplace.invoke(temp, target)
        } else {
          beforeAnchoredMoveForTest?.invoke(temp, target)
          // renameat against the held directory, not the mutable pathname.
          anchored.move(tempName, anchored, target.fileName)
        }
        verifyPublishedBytes(target, expectedBytes)
        syncParent(parent)
      } finally {
        if (created) {
          try { anchored.deleteFile(tempName) }
          catch (_: NoSuchFileException) { /* Moved into target. */ }
        }
      }
    }
  }
}
