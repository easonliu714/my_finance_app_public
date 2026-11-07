package me.movenext.flutter_pdf_text

import java.io.IOException
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.rules.TemporaryFolder
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Native terminal SHA syntax and prior-RUNNING sub-Gate; not full SHA identity binding. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PlatformResultTerminalProvenanceTest {
  @get:Rule val folder = TemporaryFolder()
  private val sourceSha = "a".repeat(64)
  private val candidateSha = "b".repeat(64)
  private val epoch = "11111111-1111-4111-8111-111111111111"

  private fun payload(
    status: String,
    source: String? = null,
    candidate: String? = null,
    pid: Int = 321
  ): JSONObject = JSONObject()
    .put("request_id", "request-A")
    .put("status", status)
    .put("worker_pid", pid)
    .put("worker_epoch", epoch)
    .apply {
      if (source != null) put("source_sha256", source)
      if (candidate != null) put("candidate_universe_sha256", candidate)
    }

  private fun writer() = PlatformResultAtomicWriter(
    syncParent = {},
    requireWorkerEpoch = true,
    requireTerminalProvenance = true
  )

  @Test fun validCompleteRequiresPriorRunning() {
    val target = folder.root.resolve("complete.json")
    val complete = payload("complete", sourceSha, candidateSha)
    val missing = assertThrows(IOException::class.java) {
      writer().write(target.path, complete.toString())
    }
    assertEquals("RESULT_COMPLETION_WITHOUT_RUNNING", missing.message)
    assertFalse(target.exists())
    writer().write(target.path, payload("running").toString())
    writer().write(target.path, complete.toString())
    assertEquals("complete", JSONObject(target.readText()).getString("status"))
  }

  @Test fun missingSourceOrCandidateDigestCannotPromoteRunning() {
    val target = folder.root.resolve("missing-sha.json")
    writer().write(target.path, payload("running").toString())
    val trusted = target.readText()
    for (bad in listOf(
      payload("complete", null, candidateSha),
      payload("complete", sourceSha, null),
      payload("complete", null, null)
    )) {
      val error = assertThrows(IOException::class.java) {
        writer().write(target.path, bad.toString())
      }
      assertEquals("RESULT_TERMINAL_PROVENANCE_INVALID", error.message)
      assertEquals(trusted, target.readText())
    }
  }

  @Test fun malformedDigestsCannotPromoteRunning() {
    val target = folder.root.resolve("malformed-sha.json")
    writer().write(target.path, payload("running").toString())
    val trusted = target.readText()
    for (bad in listOf(
      payload("complete", "a".repeat(63), candidateSha),
      payload("complete", sourceSha, "z".repeat(64)),
      payload("complete", "", candidateSha)
    )) {
      assertThrows(IOException::class.java) {
        writer().write(target.path, bad.toString())
      }
      assertEquals(trusted, target.readText())
    }
  }

  @Test fun earlyFailureNeedsNoInventedVerifiedSha() {
    val target = folder.root.resolve("early-failed.json")
    writer().write(target.path, payload("failed").toString())
    val saved = JSONObject(target.readText())
    assertEquals("failed", saved.getString("status"))
    assertFalse(saved.has("source_sha256"))
    assertFalse(saved.has("candidate_universe_sha256"))
  }

  @Test fun runningMayFailWithoutPretendingSourceWasVerified() {
    val target = folder.root.resolve("running-failed.json")
    writer().write(target.path, payload("running").toString())
    writer().write(target.path, payload("failed").toString())
    assertEquals("failed", JSONObject(target.readText()).getString("status"))
  }

  @Test fun terminalCannotBeReplacedEvenWithValidDigests() {
    val target = folder.root.resolve("immutable.json")
    writer().write(target.path, payload("running").toString())
    writer().write(target.path,
      payload("complete", sourceSha, candidateSha).toString())
    val trusted = target.readText()
    assertThrows(IOException::class.java) {
      writer().write(target.path,
        payload("complete", sourceSha, candidateSha).toString())
    }
    assertEquals(trusted, target.readText())
  }

  @Test fun foreignPidCannotPromoteValidComplete() {
    val target = folder.root.resolve("foreign-pid.json")
    writer().write(target.path, payload("running").toString())
    val trusted = target.readText()
    assertThrows(IOException::class.java) {
      writer().write(target.path,
        payload("complete", sourceSha, candidateSha, pid = 322).toString())
    }
    assertEquals(trusted, target.readText())
    assertTrue(JSONObject(trusted).getString("status") == "running")
  }
}
