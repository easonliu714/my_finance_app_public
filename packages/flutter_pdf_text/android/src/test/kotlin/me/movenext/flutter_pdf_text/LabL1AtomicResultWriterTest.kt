package me.movenext.flutter_pdf_text

import java.io.File
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

class LabL1AtomicResultWriterTest {
  @get:Rule val folder = TemporaryFolder()

  @Test fun replacementPreservesCompleteResultWithoutPendingFiles() {
    val target = folder.newFile("result.json")
    target.writeText("{\"status\":\"running\"}")
    LabL1AtomicResultWriter.replace(target.path, "{\"status\":\"complete\"}")
    assertEquals("{\"status\":\"complete\"}", target.readText())
    assertFalse(folder.root.listFiles().orEmpty().any { it.name.endsWith(".part") })
  }

  @Test fun failedRenamePreservesOldTargetAndCleansPending() {
    val occupied = folder.newFolder("result.json")
    val sentinel = File(occupied, "old-evidence")
    sentinel.writeText("keep")
    try {
      LabL1AtomicResultWriter.replace(occupied.path, "{\"status\":\"complete\"}")
      fail("directory target must fail closed")
    } catch (error: IllegalStateException) {
      assertEquals("L1_RESULT_ATOMIC_RENAME_FAILED", error.message)
    }
    assertTrue(occupied.isDirectory)
    assertEquals("keep", sentinel.readText())
    assertFalse(folder.root.listFiles().orEmpty().any { it.name.endsWith(".part") })
  }

  @Test fun concurrentHeartbeatAndTerminalWritesStayWhole() {
    val target = folder.newFile("result.json")
    val gate = CountDownLatch(1)
    val finished = CountDownLatch(16)
    val failures = AtomicInteger(0)
    val workers = (1..16).map { number ->
      thread(start = true) {
        try {
          gate.await()
          LabL1AtomicResultWriter.replace(target.path, "{\"sequence\":$number}")
        } catch (_: Throwable) {
          failures.incrementAndGet()
        } finally {
          finished.countDown()
        }
      }
    }
    gate.countDown()
    finished.await()
    workers.forEach { it.join() }
    assertEquals(0, failures.get())
    assertTrue(Regex("""\\{"sequence":\\d+\\}""").matches(target.readText()))
    assertFalse(folder.root.listFiles().orEmpty().any { it.name.endsWith(".part") })
  }
}
