package me.movenext.flutter_pdf_text

import android.net.LocalServerSocket
import java.io.Closeable
import java.security.MessageDigest
import java.io.File
import java.nio.channels.FileChannel
import java.nio.channels.FileLock
import java.nio.channels.OverlappingFileLockException
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.Path
import java.nio.file.StandardOpenOption
import java.nio.file.attribute.BasicFileAttributes

/**
 * Exclusive OS-held lease on a stable, never-deleted result sidecar inode.
 * This is NOT terminal durability, source FD custody or Android device proof.
 * Abstract-socket kernel fences precede the sidecar lock. Same-UID hostile
 * pathname/FD mutation, stable-root authority and terminal durability remain
 * separate HOLD gates; this is not an Android phone proof.
 */
internal class PlatformResultProcessLease private constructor(
  private val channel: FileChannel,
  private val lock: FileLock,
  private val resultKey: Path,
  private val kernelFences: List<Closeable>
) : Closeable {
  private var closed = false

  companion object {
    // This guards only re-entry in the same VM when a held sidecar pathname
    // is unlinked or replaced. Other processes/same-UID actors remain HOLD.
    private val activeResultKeys = mutableSetOf<Path>()
    private fun reserve(key: Path): Boolean =
      synchronized(activeResultKeys) { activeResultKeys.add(key) }
    private fun unreserve(key: Path) {
      synchronized(activeResultKeys) { activeResultKeys.remove(key) }
    }
    // Kernel abstract sockets cannot be unlinked/replaced like sidecar inodes.
    // Dual names fence lexical parent replacement and canonical symlink alias.
    private fun ownershipNames(target: Path): List<String> {
      val parent = target.parent ?: throw IllegalArgumentException("RESULT_PARENT_MISSING")
      val canonical = parent.toRealPath().resolve(target.fileName).toString()
      return listOf(target.toString(), canonical).distinct().map { identity ->
        val digest = MessageDigest.getInstance("SHA-256")
          .digest(identity.toByteArray(Charsets.UTF_8))
          .joinToString("") { "%02x".format(it.toInt() and 0xff) }
        "myfinance.result.v1.$digest"
      }.distinct().sorted()
    }

    fun tryAcquire(
      resultPath: String,
      afterOpenBeforeLock: (() -> Unit)? = null
    ): PlatformResultProcessLease? = acquire(
      resultPath, afterOpenBeforeLock
    ) { name -> LocalServerSocket(name) }

    // JVM-only explicit injection for sidecar/transition unit tests.
    // Production callers always bind real Android abstract sockets above.
    internal fun tryAcquireWithKernelFenceForTest(
      resultPath: String,
      afterOpenBeforeLock: (() -> Unit)? = null,
      bindKernel: (String) -> Closeable?
    ): PlatformResultProcessLease? = acquire(resultPath, afterOpenBeforeLock, bindKernel)

    private fun acquire(
      resultPath: String,
      afterOpenBeforeLock: (() -> Unit)?,
      bindKernel: (String) -> Closeable?
    ): PlatformResultProcessLease? {
      if (resultPath.isBlank()) return null
      val target = try { File(resultPath).absoluteFile.toPath().normalize() }
        catch (_: Exception) { return null }
      // Reserve before opening the replaceable sidecar. OS lock alone is
      // insufficient after a same-process pathname swap.
      if (!reserve(target)) return null
      var opened: FileChannel? = null
      val acquiredFences = mutableListOf<Closeable>()
      var acquired = false
      try {
        if (Files.isSymbolicLink(target)) return null
        // Do not resolve a caller-supplied symlinked parent into a different
        // lock directory. The writer independently rejects that same parent.
        val parentPath = target.parent ?: return null
        if (!Files.isDirectory(parentPath, LinkOption.NOFOLLOW_LINKS)) return null
        val parent = parentPath.toRealPath(LinkOption.NOFOLLOW_LINKS)
        // Bind every kernel name before opening a replaceable lock inode.
        // Bind failure is a hard denial, never a file-lock-only fallback.
        for (name in ownershipNames(target)) {
          val fence = bindKernel(name) ?: return null
          acquiredFences.add(fence)
        }
        val lockPath: Path = parent.resolve(".${target.fileName}.platform-worker.lock")
        if (Files.isSymbolicLink(lockPath)) return null
        val channel = FileChannel.open(
          lockPath, StandardOpenOption.CREATE, StandardOpenOption.WRITE,
          LinkOption.NOFOLLOW_LINKS
        )
        opened = channel
        // Bind this acquisition to the same regular sidecar path inode on
        // both sides of the OS lock. A same-UID rename/unlink during this
        // bounded window must not authorize a second result writer.
        val before = Files.readAttributes(
          lockPath, BasicFileAttributes::class.java, LinkOption.NOFOLLOW_LINKS)
        val openedKey = before.fileKey()
        if (!before.isRegularFile || openedKey == null) return null
        afterOpenBeforeLock?.invoke() // Deterministic native race-test seam.
        val held = try { channel.tryLock() }
          catch (_: OverlappingFileLockException) { null }
        if (held == null) return null
        val after = try {
          Files.readAttributes(
            lockPath, BasicFileAttributes::class.java, LinkOption.NOFOLLOW_LINKS)
        } catch (_: Exception) {
          held.release()
          return null
        }
        if (!after.isRegularFile || after.fileKey() != openedKey) {
          held.release()
          return null
        }
        val lease = PlatformResultProcessLease(channel, held, target, acquiredFences.toList())
        acquiredFences.clear()
        opened = null
        acquired = true
        return lease
      } catch (_: Exception) {
        return null
      } finally {
        try { opened?.close() } catch (_: Exception) {}
        for (fence in acquiredFences.asReversed()) {
          try { fence.close() } catch (_: Exception) {}
        }
        if (!acquired) unreserve(target)
      }
    }
  }

  @Synchronized
  override fun close() {
    if (closed) return
    closed = true
    try { lock.release() } finally {
      try { channel.close() } finally {
        try {
          for (fence in kernelFences.asReversed()) fence.close()
        } finally { unreserve(resultKey) }
      }
    }
  }
}
