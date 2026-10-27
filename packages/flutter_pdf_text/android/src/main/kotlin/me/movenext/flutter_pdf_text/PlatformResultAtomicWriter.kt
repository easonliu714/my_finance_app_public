package me.movenext.flutter_pdf_text

import android.system.Os
import android.system.OsConstants
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption

/**
 * Process-local serialized native result replacement. Not a cross-process
 * lease or terminal identity authority. Directory-fsync failure after move
 * is ambiguous and must never be promoted as verified durable COMPLETE.
 */
internal class PlatformResultAtomicWriter(
  private val atomicReplace: (Path, Path) -> Unit = { temp, target ->
    Files.move(temp, target,
      StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
  },
  private val syncParent: (Path) -> Unit = { directory ->
    val fd = Os.open(directory.toString(),
      OsConstants.O_RDONLY or OsConstants.O_DIRECTORY, 0)
    try { Os.fsync(fd) } finally { Os.close(fd) }
  }
) {
  @Synchronized
  fun write(path: String, content: String) {
    val target = File(path).absoluteFile.toPath()
    val parent = target.parent ?: throw IOException("RESULT_PARENT_MISSING")
    Files.createDirectories(parent)
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
