package me.movenext.flutter_pdf_text

import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class LabL1NativeResultCustodyTest {
  @get:Rule val folder = TemporaryFolder()

  @Test fun completeCannotBeOverwrittenByLateHeartbeatOrFailure() {
    val target = folder.newFile("result.json")
    val custody = LabL1NativeResultCustody()
    assertTrue(custody.publish(target.path, "running", """{"status":"running"}"""))
    assertTrue(custody.publish(target.path, "complete", """{"status":"complete"}"""))
    assertFalse(custody.publish(target.path, "running", """{"status":"running"}"""))
    assertFalse(custody.publish(target.path, "failure", """{"status":"failure"}"""))
    assertEquals("""{"status":"complete"}""", target.readText())
  }

  @Test fun failureCannotBeOverwrittenByLateCompleteOrHeartbeat() {
    val target = folder.newFile("result.json")
    val custody = LabL1NativeResultCustody()
    assertTrue(custody.publish(target.path, "failure", """{"status":"failure"}"""))
    assertFalse(custody.publish(target.path, "complete", """{"status":"complete"}"""))
    assertFalse(custody.publish(target.path, "running", """{"status":"running"}"""))
    assertEquals("""{"status":"failure"}""", target.readText())
  }

  @Test fun concurrentHeartbeatCannotRegressPublishedTerminal() {
    val target = folder.newFile("result.json")
    val custody = LabL1NativeResultCustody()
    val gate = CountDownLatch(1)
    val failures = AtomicInteger(0)
    val workers = (1..16).map {
      thread(start = true) {
        try {
          gate.await()
          custody.publish(target.path, "running", """{"status":"running"}""")
        } catch (_: Throwable) {
          failures.incrementAndGet()
        }
      }
    }
    val terminal = thread(start = true) {
      try {
        gate.await()
        custody.publish(target.path, "complete", """{"status":"complete"}""")
      } catch (_: Throwable) {
        failures.incrementAndGet()
      }
    }
    gate.countDown()
    workers.forEach { it.join() }
    terminal.join()
    assertEquals(0, failures.get())
    assertEquals("""{"status":"complete"}""", target.readText())
  }

  @Test fun failedTerminalPersistenceDoesNotClaimTerminalOrLoseRetry() {
    val occupied = folder.newFolder("result.json")
    val custody = LabL1NativeResultCustody()
    try {
      custody.publish(occupied.path, "complete", """{"status":"complete"}""")
      fail("directory target must reject atomic rename")
    } catch (error: IllegalStateException) {
      assertEquals("L1_RESULT_ATOMIC_RENAME_FAILED", error.message)
    }
    assertTrue(occupied.delete())
    assertTrue(custody.publish(occupied.path, "failure", """{"status":"failure"}"""))
    assertFalse(custody.publish(occupied.path, "running", """{"status":"running"}"""))
    assertEquals("""{"status":"failure"}""", occupied.readText())
  }

  @Test fun newWorkerUsesIndependentTerminalFence() {
    val target = folder.newFile("result.json")
    val oldWorker = LabL1NativeResultCustody()
    assertTrue(oldWorker.publish(target.path, "complete", """{"status":"complete"}"""))
    val newWorker = LabL1NativeResultCustody()
    assertTrue(newWorker.publish(target.path, "running", """{"status":"running"}"""))
    assertFalse(oldWorker.publish(target.path, "running", """{"status":"old"}"""))
    assertEquals("""{"status":"running"}""", target.readText())
  }
}
