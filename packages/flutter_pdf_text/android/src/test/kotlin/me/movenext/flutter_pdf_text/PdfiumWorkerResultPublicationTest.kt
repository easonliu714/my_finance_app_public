package me.movenext.flutter_pdf_text

import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import org.junit.Assert.*
import org.junit.Test

class PdfiumWorkerResultPublicationTest {
  @Test fun runningBeforeTerminalIsPublishedButLateHeartbeatCannotOverwriteComplete() {
    val writes = mutableListOf<String>()
    val gate = PdfiumWorkerResultPublication { writes.add(it) }
    assertTrue(gate.publishRunning("running"))
    assertTrue(gate.publishTerminal("complete"))
    assertFalse(gate.publishRunning("stale-running"))
    assertFalse(gate.publishTerminal("failed"))
    assertEquals(listOf("running", "complete"), writes)
  }

  @Test fun failedTerminalRenameDoesNotClaimSuccessAndAllowsRetry() {
    var reject = true
    val writes = mutableListOf<String>()
    val gate = PdfiumWorkerResultPublication {
      if (reject) throw IOException("rename failed")
      writes.add(it)
    }
    try {
      gate.publishTerminal("complete")
      fail("failed terminal write was accepted")
    } catch (_: IOException) {}
    reject = false
    assertTrue(gate.publishTerminal("failed"))
    assertFalse(gate.publishRunning("stale"))
    assertEquals(listOf("failed"), writes)
  }

  @Test fun concurrentHeartbeatCannotPublishAfterTerminal() {
    val entered = CountDownLatch(1)
    val release = CountDownLatch(1)
    val writes = mutableListOf<String>()
    val gate = PdfiumWorkerResultPublication {
      if (it == "running") {
        entered.countDown()
        assertTrue(release.await(5, TimeUnit.SECONDS))
      }
      writes.add(it)
    }
    val heartbeat = thread { gate.publishRunning("running") }
    assertTrue(entered.await(5, TimeUnit.SECONDS))
    val terminal = thread { gate.publishTerminal("complete") }
    release.countDown()
    heartbeat.join(5000)
    terminal.join(5000)
    assertFalse(heartbeat.isAlive)
    assertFalse(terminal.isAlive)
    assertFalse(gate.publishRunning("late"))
    assertEquals(listOf("running", "complete"), writes)
  }

  @Test fun nextAdmittedWorkerCanResetTerminalState() {
    val writes = mutableListOf<String>()
    val gate = PdfiumWorkerResultPublication { writes.add(it) }
    assertTrue(gate.publishTerminal("complete-first"))
    gate.reset()
    assertTrue(gate.publishRunning("running-second"))
    assertTrue(gate.publishTerminal("complete-second"))
    assertEquals(listOf("complete-first", "running-second", "complete-second"), writes)
  }
}
