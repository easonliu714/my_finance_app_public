package me.movenext.flutter_pdf_text

import java.io.Closeable
import java.io.File
import java.nio.channels.FileChannel
import java.nio.channels.FileLock
import java.nio.channels.OverlappingFileLockException
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.Path
import java.nio.file.StandardOpenOption

/**
 * Exclusive OS-held lease on a stable, never-deleted result sidecar inode.
 * This is NOT terminal durability, source FD custody or Android device proof.
 */
internal class PlatformResultProcessLease private constructor(
  private val channel: FileChannel,
  private val lock: FileLock
) : Closeable {
  companion object {
    fun tryAcquire(resultPath: String): PlatformResultProcessLease? {
      if (resultPath.isBlank()) return null
      var opened: FileChannel? = null
      try {
        val target = File(resultPath).absoluteFile.toPath().normalize()
        if (Files.isSymbolicLink(target)) return null
        val parent = target.parent?.toRealPath() ?: return null
        if (!Files.isDirectory(parent, LinkOption.NOFOLLOW_LINKS)) return null
        val lockPath: Path = parent.resolve(".${target.fileName}.platform-worker.lock")
        if (Files.isSymbolicLink(lockPath)) return null
        val channel = FileChannel.open(
          lockPath, StandardOpenOption.CREATE, StandardOpenOption.WRITE,
          LinkOption.NOFOLLOW_LINKS
        )
        opened = channel
        val held = try { channel.tryLock() }
          catch (_: OverlappingFileLockException) { null }
        if (held == null) return null
        opened = null
        return PlatformResultProcessLease(channel, held)
      } catch (_: Exception) {
        return null
      } finally {
        try { opened?.close() } catch (_: Exception) {}
      }
    }
  }

  override fun close() {
    try { lock.release() } finally { channel.close() }
  }
}
