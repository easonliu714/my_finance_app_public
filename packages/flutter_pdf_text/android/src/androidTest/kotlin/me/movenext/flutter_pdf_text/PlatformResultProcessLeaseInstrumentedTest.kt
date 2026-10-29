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
import android.net.LocalServerSocket
import java.security.MessageDigest
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import java.io.Closeable
import java.io.IOException
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.nio.file.SecureDirectoryStream
import java.nio.file.Path
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
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

  /**
   * C16 API35 real-kernel negative/positive: a same-UID prebound abstract
   * socket name must deny the lease BEFORE creating any sidecar. Releasing
   * the foreign binder must permit a fresh acquisition. This is not
   * protection against a permanently hostile same-UID prebinder (DoS HOLD).
   */
  @Test fun preboundKernelIdentityDeniesLeaseWithoutSidecarThenRecovers() {
    val result = isolatedResult()
    val identity = result.toPath().toAbsolutePath().normalize().toString()
    val digest = MessageDigest.getInstance("SHA-256")
      .digest(identity.toByteArray(Charsets.UTF_8))
      .joinToString("") { "%02x".format(it.toInt() and 0xff) }
    val sidecar = File(result.parentFile, ".result.json.platform-worker.lock").toPath()
    val prebound = LocalServerSocket("myfinance.result.v1.$digest")
    try {
      assertNull("PREBOUND_KERNEL_NAME_MUST_FAIL_CLOSED",
        PlatformResultProcessLease.tryAcquire(result.path))
      assertFalse("No replaceable sidecar may be opened on kernel bind denial",
        Files.exists(sidecar))
    } finally {
      prebound.close()
    }
    val recovered = PlatformResultProcessLease.tryAcquire(result.path)
    assertNotNull("Released kernel name must permit acquisition", recovered)
    recovered!!.close()
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

  @Test fun ancestorAliasCannotCreateSecondAndroidOwner() {
    val result = isolatedResult()
    val cacheRoot = result.parentFile.parentFile.toPath()
    val aliasRoot = cacheRoot.resolve("ancestor-alias-${UUID.randomUUID()}")
    Files.createSymbolicLink(aliasRoot, cacheRoot)
    val aliasResult = aliasRoot.resolve(result.parentFile.name).resolve(result.name)
    val first = PlatformResultProcessLease.tryAcquire(result.path)
    assertNotNull(first)
    try {
      RemoteLease(targetContext).use { remote ->
        val denied = remote.call(PlatformLeaseProbeService.ACQUIRE, aliasResult.toString())
        assertIndependentSameUid(denied)
        assertFalse("CROSS_PROCESS_ALIAS_DOUBLE_OWNER", denied.getBoolean("acquired"))
      }
    } finally {
      first!!.close()
      Files.deleteIfExists(aliasRoot)
    }
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

  /**
   * C18 Android API35 positive: the real production writer publishes exact
   * bytes and directory-fsync succeeds without a hostile parent replacement.
   * This is emulator runtime evidence, not physical phone or durability after
   * a power loss.
   */
  @Test fun c18NormalAndroidResultPublicationMatchesTrustedBytes() {
    val parent = File(targetContext.cacheDir, "pr45-c12-${UUID.randomUUID()}")
    assertTrue("C18 private test directory", parent.mkdirs())
    try {
      val target = File(parent, "result.json")
      PlatformResultAtomicWriter(protectTerminal = false).write(
        target.absolutePath, "TRUSTED_RESULT")
      assertEquals("TRUSTED_RESULT", target.readText(Charsets.UTF_8))
    } finally {
      parent.deleteRecursively()
    }
  }

  /**
   * C18 real independent Android PID/UID witness for C12. The DEBUG-only
   * remote process replaces the parent and temporary pathname while the
   * production writer is paused at its existing atomicReplace seam.
   * A detected IOException is not enough: a forged consumer-visible result
   * must not survive. Expected RED until an actual publication protocol
   * prevents promotion of untrusted bytes; never mask or skip this assertion.
   */
  @Test fun c18CrossPidParentSwapMustNotExposeForgedResultAfterFailedPublish() {
    val parent = File(targetContext.cacheDir, "pr45-c12-${UUID.randomUUID()}")
    assertTrue("C18 private test directory", parent.mkdirs())
    val target = File(parent, "result.json")
    val displaced = File(parent.parentFile, parent.name + "-held")
    try {
      RemoteLease(targetContext).use { remote ->
        var injected = false
        val writer = PlatformResultAtomicWriter(
          protectTerminal = false,
          atomicReplace = { temp, destination ->
            val swap = remote.call(PlatformLeaseProbeService.SWAP_C12_PARENT, temp.toString())
            assertIndependentSameUid(swap)
            assertTrue("C18_REMOTE_PARENT_SWAP_FAILED", swap.getBoolean("swapped"))
            injected = true
            Files.move(temp, destination,
              StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
          },
          syncParent = {
            throw AssertionError("C18_FORGED_PUBLICATION_MUST_NOT_REACH_FSYNC")
          }
        )
        var failure: IOException? = null
        try {
          writer.write(target.absolutePath, "TRUSTED_RESULT")
        } catch (error: IOException) {
          failure = error
        }
        assertTrue("C18 remote process must have injected swap", injected)
        assertNotNull("C18 writer must fail closed on forged bytes", failure)
        assertEquals("RESULT_PUBLICATION_CONTENT_MISMATCH", failure!!.message)
        println("C18_API35_CROSS_PID_PUBLICATION local_pid=${Process.myPid()} " +
          "result_visible=${Files.exists(target.toPath())}")
        assertFalse("C18_ANDROID_CROSS_PID_FORGED_RESULT_VISIBLE_AFTER_FAILED_PUBLICATION",
          Files.exists(target.toPath()))
      }
    } finally {
      parent.deleteRecursively()
      displaced.deleteRecursively()
    }
  }

  /**
   * C19 API35 capability witness: SecureDirectoryStream.move must use the
   * already-open original directory inode, even after an independent same-UID
   * Android PID renames/replaces the parent and plants a forged temp pathname.
   * This does NOT prove the public replacement directory is trustworthy, nor
   * close C17/C18 consumer-visible forged-result RED. It proves only the
   * FD-anchored publication primitive needed for a future production fix.
   */
  @Test fun c19SecureDirectoryStreamMoveAnchorsOriginalParentAcrossCrossPidSwap() {
    val parent = File(targetContext.cacheDir, "pr45-c12-${UUID.randomUUID()}")
    assertTrue("C19 isolated private directory", parent.mkdirs())
    val target = File(parent, "result.json")
    val displaced = File(parent.parentFile, parent.name + "-held")
    try {
      RemoteLease(targetContext).use { remote ->
        val temp = Files.createTempFile(parent.toPath(), ".result.json.", ".tmp")
        Files.write(temp, "TRUSTED_RESULT".toByteArray(Charsets.UTF_8))
        Files.newDirectoryStream(parent.toPath()).use { directory ->
          assertTrue("C19_ANDROID_SECURE_DIRECTORY_STREAM_REQUIRED",
            directory is SecureDirectoryStream<*>)
          @Suppress("UNCHECKED_CAST")
          val anchored = directory as SecureDirectoryStream<Path>
          val swap = remote.call(PlatformLeaseProbeService.SWAP_C12_PARENT, temp.toString())
          assertIndependentSameUid(swap)
          assertTrue("C19_REMOTE_PARENT_SWAP_FAILED", swap.getBoolean("swapped"))
          anchored.move(temp.fileName, anchored, target.toPath().fileName)
        }
        assertEquals("C19 original inode receives trusted bytes",
          "TRUSTED_RESULT", File(displaced, "result.json").readText(Charsets.UTF_8))
        assertFalse("C19_ANCHORED_MOVE_MUST_NOT_PUBLISH_TO_REPLACED_PARENT",
          Files.exists(target.toPath()))
        assertTrue("C19 adversary-created new-parent temp remains distinct",
          Files.exists(File(parent, temp.fileName.toString()).toPath()))
      }
    } finally {
      parent.deleteRecursively()
      displaced.deleteRecursively()
    }
  }

}
