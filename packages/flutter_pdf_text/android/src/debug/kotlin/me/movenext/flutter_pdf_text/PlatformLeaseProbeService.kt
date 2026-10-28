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

/**
 * DEBUG-ONLY remote process probe for authorized API35 instrumentation.
 * Never exported, never included in release; it does not write any ledger.
 * The Messenger replies with PID/UID and the result of a real OS lease.
 */
class PlatformLeaseProbeService : Service() {
  companion object {
    const val ACQUIRE = 1
    const val RELEASE = 2
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
