package me.movenext.flutter_pdf_text

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PdfiumWorkerSingleFlightAdmissionTest {
  @Test fun rejectsSecondHeavyRequestUntilOwnerFinishes() {
    val gate = PdfiumWorkerSingleFlightAdmission()
    assertTrue(gate.tryStart("first", "/cache/first.json"))
    assertTrue(gate.isActive())
    assertFalse(gate.tryStart("second", "/cache/second.json"))
    assertTrue(gate.isActivePath("/cache/first.json"))
    assertFalse(gate.isActivePath("/cache/second.json"))
    assertTrue(gate.finish("first"))
    assertFalse(gate.isActive())
    assertTrue(gate.tryStart("second", "/cache/second.json"))
    assertTrue(gate.finish("second"))
  }

  @Test fun foreignCompletionCannotStopOrReleaseActiveWorker() {
    val gate = PdfiumWorkerSingleFlightAdmission()
    assertTrue(gate.tryStart("live", "/cache/live.json"))
    assertFalse(gate.finish("other"))
    assertFalse(gate.finish(""))
    assertFalse(gate.tryStart("competing", "/cache/other.json"))
    assertTrue(gate.isActivePath("/cache/live.json"))
    assertTrue(gate.finish("live"))
    assertFalse(gate.finish("live"))
  }

  @Test fun nullOrBlankAdmissionNeverAcquiresNativeWorker() {
    val gate = PdfiumWorkerSingleFlightAdmission()
    assertFalse(gate.tryStart("", "/cache/result.json"))
    assertFalse(gate.tryStart("task", " "))
    assertFalse(gate.isActive())
    assertTrue(gate.tryStart("task", "/cache/result.json"))
    assertFalse(gate.tryStart("task", "/cache/result.json"))
    assertTrue(gate.finish("task"))
  }

  @Test fun concurrentAdmissionsHaveExactlyOneWinnerAndAllowRecovery() {
    val gate = PdfiumWorkerSingleFlightAdmission()
    val ready = CountDownLatch(12)
    val go = CountDownLatch(1)
    val done = CountDownLatch(12)
    val winners = AtomicInteger(0)
    val threads = (1..12).map { number ->
      thread {
        try {
          ready.countDown()
          if (go.await(10, TimeUnit.SECONDS) &&
              gate.tryStart("request-$number", "/cache/$number.json")) {
            winners.incrementAndGet()
          }
        } finally {
          done.countDown()
        }
      }
    }
    assertTrue(ready.await(10, TimeUnit.SECONDS))
    go.countDown()
    assertTrue(done.await(10, TimeUnit.SECONDS))
    threads.forEach { it.join(1000) }
    assertEquals(1, winners.get())
    assertTrue(gate.isActive())
    // Every failed request must remain excluded while the winner is running.
    assertFalse(gate.tryStart("replay", "/cache/replay.json"))
    var released = false
    for (number in 1..12) {
      if (gate.finish("request-$number")) {
        assertFalse(released)
        released = true
      }
    }
    assertTrue(released)
    assertTrue(gate.tryStart("retry", "/cache/retry.json"))
    assertTrue(gate.finish("retry"))
  }
}
