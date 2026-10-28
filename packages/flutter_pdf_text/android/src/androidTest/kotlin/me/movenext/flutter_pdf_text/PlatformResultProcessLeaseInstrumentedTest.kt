package me.movenext.flutter_pdf_text

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.Process
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import java.io.Closeable
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * API35 instrumentation, not Robolectric. The test process and the debug-only
 * target Service have distinct PIDs and the SAME app UID. No production data.
 * The pathname-swap negative is expected RED on the current production lease;
 * CI only compiles it until an authorized emulator/device executes it.
 */
@RunWith(AndroidJUnit4::class)
@SdkSuppress(minSdkVersion = 35)
class PlatformResultProcessLeaseInstrumentedTest {
  private val targetContext get() = InstrumentationRegistry.getInstrumentation().targetContext

  private class RemoteLease(private val context: Context) : Closeable {
    private val connected = CountDownLatch(1)
    private var remote: Messenger? = null
    private val connection = object : ServiceConnection {
      override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
        if (binder != null) remote = Messenger(binder)
        connected.countDown()
      }
      override fun onServiceDisconnected(name: ComponentName?) {
        remote = null
      }
    }

    init {
      val intent = Intent().setClassName(
        context.packageName, "me.movenext.flutter_pdf_text.PlatformLeaseProbeService")
      assertTrue("Debug-only lease probe must be bound", context.bindService(
        intent, connection, Context.BIND_AUTO_CREATE))
      assertTrue("Remote lease probe bind timed out", connected.await(15, TimeUnit.SECONDS))
      assertNotNull("Remote lease probe binder missing", remote)
    }

    fun call(command: Int, path: String = ""): Bundle {
      val replied = CountDownLatch(1)
      var result: Bundle? = null
      val receiver = Messenger(Handler(Looper.getMainLooper()) { response ->
        if (response.what == command) {
          result = response.data
          replied.countDown()
        }
        true
      })
      val request = Message.obtain(null, command)
      request.replyTo = receiver
      request.data = Bundle().apply { putString("path", path) }
      val sender = remote ?: error("REMOTE_PROBE_DISCONNECTED")
      sender.send(request)
      assertTrue("Remote probe reply timed out", replied.await(15, TimeUnit.SECONDS))
      return result ?: error("REMOTE_PROBE_EMPTY_REPLY")
    }

    override fun close() {
      try { if (remote != null) call(PlatformLeaseProbeService.RELEASE) }
      finally { context.unbindService(connection) }
    }
  }

  private fun isolatedResult(): File {
    val dir = File(targetContext.cacheDir, "pr45-lease-${UUID.randomUUID()}")
    assertTrue("Isolated probe directory must be created", dir.mkdirs())
    return File(dir, "result.json").apply { writeText("{}") }
  }

  private fun assertIndependentSameUid(reply: Bundle) {
    assertNotEquals("Must be a different Android PID", Process.myPid(), reply.getInt("pid"))
    assertEquals("Must be the same Android app UID", Process.myUid(), reply.getInt("uid"))
    assertFalse("Remote probe failed: ${reply.getString("error")}", reply.containsKey("error"))
    val selinux = reply.getString("selinux").orEmpty()
    assertTrue("Android SELinux context unavailable: $selinux", selinux.startsWith("u:r:"))
    println("PR45_API35_PID_UID_SELINUX local_pid=${Process.myPid()} remote_pid=${reply.getInt("pid")} local_uid=${Process.myUid()} remote_uid=${reply.getInt("uid")} remote_selinux=$selinux")
  }

  @Test fun unchangedSidecarRejectsSecondAndroidProcessUntilRelease() {
    val result = isolatedResult()
    val first = PlatformResultProcessLease.tryAcquire(result.path)
    assertNotNull(first)
    try {
      RemoteLease(targetContext).use { remote ->
        val denied = remote.call(PlatformLeaseProbeService.ACQUIRE, result.path)
        assertIndependentSameUid(denied)
        assertFalse("B must not own A's unchanged sidecar", denied.getBoolean("acquired"))
        first!!.close()
        val recovered = remote.call(PlatformLeaseProbeService.ACQUIRE, result.path)
        assertIndependentSameUid(recovered)
        assertTrue("B must acquire after A releases", recovered.getBoolean("acquired"))
      }
    } finally { first?.close() }
  }

  @Test fun sidecarReplacementCannotCreateSecondAndroidOwnerWhileFirstAlive() {
    val result = isolatedResult()
    val first = PlatformResultProcessLease.tryAcquire(result.path)
    assertNotNull(first)
    val sidecar = File(result.parentFile, ".result.json.platform-worker.lock").toPath()
    val displaced = sidecar.resolveSibling("original-held-sidecar.lock")
    try {
      RemoteLease(targetContext).use { remote ->
        val baseline = remote.call(PlatformLeaseProbeService.ACQUIRE, result.path)
        assertIndependentSameUid(baseline)
        assertFalse("Baseline ownership must be exclusive", baseline.getBoolean("acquired"))
        Files.move(sidecar, displaced, StandardCopyOption.ATOMIC_MOVE)
        Files.createFile(sidecar)
        // Expected RED with current pathname-based kernel lock: B can lock the
        // new inode while A still holds the displaced old inode. No COMPLETE.
        val afterSwap = remote.call(PlatformLeaseProbeService.ACQUIRE, result.path)
        assertIndependentSameUid(afterSwap)
        assertFalse("CROSS_PROCESS_DOUBLE_OWNER_AFTER_SIDECAR_SWAP",
          afterSwap.getBoolean("acquired"))
        first!!.close()
        val recovered = remote.call(PlatformLeaseProbeService.ACQUIRE, result.path)
        assertIndependentSameUid(recovered)
        assertTrue("B must recover ownership after A releases", recovered.getBoolean("acquired"))
      }
    } finally { first?.close() }
  }
}
