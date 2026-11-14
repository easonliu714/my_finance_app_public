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

/** C23 JVM/Robolectric API35 regression, NOT independent Android PID proof. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PlatformPdfiumResultPublisherTest {
  @get:Rule val folder = TemporaryFolder()
  private val epoch = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
  private val otherEpoch = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"

  private fun publisher(writer: PlatformResultAtomicWriter =
    PlatformResultAtomicWriter(
      syncParent = {},
      requireWorkerEpoch = true,
      requireTerminalProvenance = true
    )
  ) = PlatformPdfiumResultPublisher(writer)

  private fun payload(status: String, workerEpoch: String = epoch): String =
    JSONObject()
      .put("request_id", "C23-REQUEST")
      .put("status", status)
      .put("worker_pid", 12345)
      .put("worker_epoch", workerEpoch)
      .put("source_sha256", "a".repeat(64))
      .put("candidate_universe_sha256", "b".repeat(64))
      .toString()

  @Test fun runningToCompleteRequiresEpochAndRejectsLateOverwrite() {
    val target = folder.root.resolve("c23-positive.json")
    val publisher = publisher()
    publisher.publish(target.path, payload("running"))
    publisher.publish(target.path, payload("complete"))
    val terminal = target.readText()
    assertEquals("complete", JSONObject(terminal).getString("status"))
    assertThrows(IOException::class.java) {
      publisher.publish(target.path, payload("running"))
    }
    assertEquals(terminal, target.readText())
  }

  @Test fun foreignWorkerEpochCannotPromoteRunningToComplete() {
    val target = folder.root.resolve("c23-foreign.json")
    val publisher = publisher()
    publisher.publish(target.path, payload("running"))
    val running = target.readText()
    val error = assertThrows(IOException::class.java) {
      publisher.publish(target.path, payload("complete", otherEpoch))
    }
    assertEquals("RESULT_WORKER_IDENTITY_MISMATCH", error.message)
    assertEquals(running, target.readText())
  }

  @Test fun completionWithoutRunningMustFailClosed() {
    val target = folder.root.resolve("c23-no-running.json")
    val error = assertThrows(IOException::class.java) {
      publisher().publish(target.path, payload("complete"))
    }
    assertEquals("RESULT_COMPLETION_WITHOUT_RUNNING", error.message)
    assertFalse(target.exists())
  }

  @Test fun renameFailureMustNeverFallbackToDirectResultWrite() {
    val target = folder.root.resolve("c23-rename-failure.json")
    val publisher = publisher(PlatformResultAtomicWriter(
      atomicReplace = { _, _ -> throw IOException("C23_INJECTED_RENAME_FAILURE") },
      syncParent = {},
      requireWorkerEpoch = true,
      requireTerminalProvenance = true
    ))
    val error = assertThrows(IOException::class.java) {
      publisher.publish(target.path, payload("running"))
    }
    assertEquals("C23_INJECTED_RENAME_FAILURE", error.message)
    assertFalse("No direct-write fallback may create result", target.exists())
    assertFalse("Temporary files must be cleaned",
      folder.root.listFiles().orEmpty().any { it.name.endsWith(".tmp") })
  }
}
