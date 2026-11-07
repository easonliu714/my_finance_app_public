package me.movenext.flutter_pdf_text

import android.app.Service
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.Process
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption

/**
 * DEBUG-ONLY remote process probe for authorized API35 instrumentation.
 * Never exported, never included in release; it does not write any ledger.
 * The Messenger replies with PID/UID and the result of a real OS lease.
 */
class PlatformLeaseProbeService : Service() {
  companion object {
    const val ACQUIRE = 1
    const val RELEASE = 2
    const val SWAP_C12_PARENT = 3
  }

  private var held: PlatformResultProcessLease? = null
  private val messenger = Messenger(Handler(Looper.getMainLooper()) { request ->
    val reply = Message.obtain(null, request.what)
    val data = Bundle()
    data.putInt("pid", Process.myPid())
    data.putInt("uid", Process.myUid())
    data.putString("selinux", try {
      File("/proc/self/attr/current").readText().trim()
    } catch (_: Exception) { "unavailable" })
    try {
      when (request.what) {
        ACQUIRE -> {
          val path = request.data.getString("path").orEmpty()
          if (held == null && path.isNotBlank()) {
            held = PlatformResultProcessLease.tryAcquire(path)
          }
          data.putBoolean("acquired", held != null)
        }
        RELEASE -> {
          held?.close()
          held = null
          data.putBoolean("released", true)
        }
        // C18 DEBUG-ONLY deterministic cross-PID publication fault injection.
        // Restrict to an isolated, immediate cache child and the writer's
        // generated temp name. Never expose this command in release builds.
        SWAP_C12_PARENT -> {
          val temp = File(request.data.getString("path").orEmpty())
            .toPath().toAbsolutePath().normalize()
          val parent = temp.parent ?: throw IOException("C18_TEMP_PARENT_MISSING")
          val cache = cacheDir.toPath().toAbsolutePath().normalize()
          // C21A: allow only the two UUID-scoped C12/C21 Android test roots.
          // The production writer test uses pr45-c21-; a C18-only prefix
          // incorrectly returned IOException before any adversarial swap.
          val allowedParent = Regex(
            "^pr45-c(?:12|21)-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
          ).matches(parent.fileName.toString())
          if (parent.parent != cache ||
              !allowedParent ||
              !temp.fileName.toString().startsWith(".result.json.") ||
              !temp.fileName.toString().endsWith(".tmp") ||
              !Files.isDirectory(parent, LinkOption.NOFOLLOW_LINKS) ||
              !Files.isRegularFile(temp, LinkOption.NOFOLLOW_LINKS)) {
            throw IOException("C18_DEBUG_SCOPE_DENIED")
          }
          val displaced = parent.resolveSibling(parent.fileName.toString() + "-held")
          if (Files.exists(displaced, LinkOption.NOFOLLOW_LINKS)) {
            throw IOException("C18_DISPLACED_ALREADY_EXISTS")
          }
          Files.move(parent, displaced, StandardCopyOption.ATOMIC_MOVE)
          Files.createDirectory(parent)
          Files.write(parent.resolve(temp.fileName), "FORGED_RESULT".toByteArray(Charsets.UTF_8),
            StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE)
          data.putBoolean("swapped", true)
        }
        else -> data.putString("error", "UNKNOWN_PROBE_COMMAND")
      }
    } catch (error: Exception) {
      data.putString("error", error.javaClass.simpleName)
    }
    reply.data = data
    try { request.replyTo?.send(reply) } catch (_: Exception) {}
    true
  })

  override fun onBind(intent: Intent?): IBinder = messenger.binder

  override fun onDestroy() {
    try { held?.close() } finally {
      held = null
      super.onDestroy()
    }
  }
}
