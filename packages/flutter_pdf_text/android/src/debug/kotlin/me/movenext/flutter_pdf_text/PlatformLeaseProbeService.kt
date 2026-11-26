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
import java.util.concurrent.CountDownLatch
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
    const val FLOOR_CAS_ISOLATED = 4
    const val FLOOR_CAS_PREPARE = 5
    const val FLOOR_CAS_GO = 6
    const val TERMINATE_ISOLATED_PROCESS = 7
  }

  private var held: PlatformResultProcessLease? = null
  private var pendingFloorGate: CountDownLatch? = null
  private var pendingFloorWorker: Thread? = null
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
        // V25-E-52: only the fixed noBackup test floor; no caller-supplied paths,
        // no ledger authority and no production activation.
        FLOOR_CAS_ISOLATED -> {
          val floor = InvoiceAwardNoBackupFloorCandidate(this@PlatformLeaseProbeService)
          data.putBoolean("advanced", floor.compareAndAdvance(
            request.data.getLong("expected"), request.data.getLong("next")))
          data.putLong("floor", floor.readFloor() ?: -1L)
        }
        // V25-F-52: a remote OS worker is READY before the local process
        // releases the race. The worker never accepts a caller-supplied path.
        FLOOR_CAS_PREPARE -> {
          if (pendingFloorWorker?.isAlive == true || pendingFloorGate != null) {
            throw IllegalStateException("FLOOR_RACE_ALREADY_PREPARED")
          }
          val expected = request.data.getLong("expected")
          val next = request.data.getLong("next")
          val recipient = request.replyTo ?: throw IllegalArgumentException("FLOOR_REPLY_REQUIRED")
          val gate = CountDownLatch(1)
          pendingFloorGate = gate
          val worker = Thread {
            try {
              gate.await()
              val floor = InvoiceAwardNoBackupFloorCandidate(this@PlatformLeaseProbeService)
              val result = Message.obtain(null, FLOOR_CAS_ISOLATED)
              result.data = Bundle().apply {
                putInt("pid", Process.myPid())
                putInt("uid", Process.myUid())
                putBoolean("advanced", floor.compareAndAdvance(expected, next))
                putLong("floor", floor.readFloor() ?: -1L)
              }
              recipient.send(result)
            } catch (error: Exception) {
              try {
                val failed = Message.obtain(null, FLOOR_CAS_ISOLATED)
                failed.data = Bundle().apply { putString("error", error.javaClass.simpleName) }
                recipient.send(failed)
              } catch (_: Exception) { }
            }
          }
          pendingFloorWorker = worker
          worker.start()
          data.putBoolean("ready", true)
        }
        // V25-G-52: debug-only, non-exported service terminates ONLY its own
        // separate OS process. Reply first so instrumentation can observe binder
        // death; never expose process termination through a release manifest.
        TERMINATE_ISOLATED_PROCESS -> {
          if (!android.app.Application.getProcessName().endsWith(":pr45_native_lease_probe")) {
            throw IllegalStateException("INVALID_REMOTE_PROCESS_ID")
          }
          data.putBoolean("terminating", true)
          Handler(Looper.getMainLooper()).postDelayed({
            Process.killProcess(Process.myPid())
          }, 250L)
        }
        FLOOR_CAS_GO -> {
          val gate = pendingFloorGate ?: throw IllegalStateException("FLOOR_RACE_NOT_PREPARED")
          pendingFloorGate = null
          gate.countDown()
          data.putBoolean("released", true)
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
    pendingFloorGate?.countDown()
    pendingFloorGate = null
    try { held?.close() } finally {
      held = null
      super.onDestroy()
    }
  }
}
