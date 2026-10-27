package me.movenext.flutter_pdf_text

import java.io.IOException
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.rules.TemporaryFolder
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * API35 native JVM PID + process-epoch transition fence. These synthetic
 * tests do NOT prove independent Android process death, sidecar inode custody
 * or resistance to same-UID tampering.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PlatformResultWorkerEpochTest {
  @get:Rule val folder = TemporaryFolder()

  private val epochA = "11111111-1111-4111-8111-111111111111"
  private val epochB = "22222222-2222-4222-8222-222222222222"

  private fun payload(
    request: String = "request-A",
    status: String = "running",
    pid: Int = 321,
    epoch: String = epochA
  ): JSONObject = JSONObject()
    .put("request_id", request)
    .put("status", status)
    .put("worker_pid", pid)
    .put("worker_epoch", epoch)

  private fun writer() = PlatformResultAtomicWriter(
    syncParent = {}, requireWorkerEpoch = true)

  @Test fun samePidAndEpochCanPublishRunningThenComplete() {
    val target = folder.root.resolve("complete.json")
    writer().write(target.path, payload().toString())
    writer().write(target.path, payload(status = "complete").toString())
    assertEquals("complete", JSONObject(target.readText()).getString("status"))
    assertEquals(epochA, JSONObject(target.readText()).getString("worker_epoch"))
  }

  @Test fun foreignPidCannotOverwriteRunning() {
    val target = folder.root.resolve("foreign-pid.json")
    writer().write(target.path, payload().toString())
    val trusted = target.readText()
    assertThrows(IOException::class.java) {
      writer().write(target.path, payload(pid = 322).toString())
    }
    assertEquals(trusted, target.readText())
  }

  @Test fun reusedPidWithDifferentProcessEpochCannotInheritRunning() {
    val target = folder.root.resolve("pid-reuse.json")
    writer().write(target.path, payload().toString())
    val trusted = target.readText()
    assertThrows(IOException::class.java) {
      writer().write(target.path, payload(status = "complete", epoch = epochB).toString())
    }
    assertEquals(trusted, target.readText())
  }

  @Test fun missingOrMalformedIdentityCannotCreateResult() {
    val target = folder.root.resolve("missing.json")
    for (invalid in listOf(
      payload().apply { remove("worker_pid") },
      payload().apply { remove("worker_epoch") },
      payload(pid = 0),
      payload(epoch = "not-a-uuid")
    )) {
      assertThrows(IOException::class.java) {
        writer().write(target.path, invalid.toString())
      }
      assertFalse(target.exists())
    }
  }

  @Test fun legacyRunningWithoutEpochCannotBePromoted() {
    val target = folder.root.resolve("legacy.json")
    val legacy = payload().apply { remove("worker_epoch") }.toString()
    target.writeText(legacy)
    assertThrows(IOException::class.java) {
      writer().write(target.path, payload(status = "complete").toString())
    }
    assertEquals(legacy, target.readText())
  }

  @Test fun matchingFailedTerminalIsImmutable() {
    val target = folder.root.resolve("failed.json")
    writer().write(target.path, payload(status = "failed").toString())
    val trusted = target.readText()
    assertThrows(IOException::class.java) {
      writer().write(target.path, payload(status = "complete").toString())
    }
    assertEquals(trusted, target.readText())
  }

  @Test fun foreignRequestWithSamePidAndEpochIsRejected() {
    val target = folder.root.resolve("foreign-request.json")
    writer().write(target.path, payload().toString())
    val trusted = target.readText()
    assertThrows(IOException::class.java) {
      writer().write(target.path, payload(request = "request-B").toString())
    }
    assertEquals(trusted, target.readText())
  }

  @Test fun sameIdentityCanTransitionRunningToFailedOnlyOnce() {
    val target = folder.root.resolve("failed-transition.json")
    writer().write(target.path, payload().toString())
    writer().write(target.path, payload(status = "failed").toString())
    val trusted = target.readText()
    assertThrows(IOException::class.java) {
      writer().write(target.path, payload().toString())
    }
    assertEquals(trusted, target.readText())
  }
}
