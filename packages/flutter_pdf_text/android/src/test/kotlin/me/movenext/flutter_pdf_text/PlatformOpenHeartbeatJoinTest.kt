package me.movenext.flutter_pdf_text

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Native JVM concurrency regressions for the actual Platform worker's
 * heartbeat stop-and-join function. Synthetic threads only: no official
 * PDF, ledger, SQLite, network, or real Android process evidence.
 */
class PlatformOpenHeartbeatJoinTest {
  @Test
  fun sleepingHeartbeatQuiescesWithoutPublishingAfterStop() {
    val opening = AtomicBoolean(true)
    val started = CountDownLatch(1)
    val writes = AtomicInteger()
    val heartbeat = thread(start = true, isDaemon = true) {
      started.countDown()
      while (opening.get()) {
        try {
          Thread.sleep(60_000)
          if (opening.get()) writes.incrementAndGet()
        } catch (_: InterruptedException) {
          break
        }
      }
    }
    assertTrue(started.await(2, TimeUnit.SECONDS))
    stopAndJoinPlatformOpenHeartbeat(opening, heartbeat)
    assertFalse(heartbeat.isAlive)
    assertFalse(opening.get())
    assertEquals(0, writes.get())
  }

  @Test
  fun inFlightHeartbeatWriteMustFinishBeforeStopReturns() {
    val opening = AtomicBoolean(true)
    val inWrite = CountDownLatch(1)
    val releaseWrite = CountDownLatch(1)
    val stopped = CountDownLatch(1)
    val writes = AtomicInteger()
    val heartbeat = thread(start = true, isDaemon = true) {
      if (opening.get()) {
        inWrite.countDown()
        while (releaseWrite.count > 0L) {
          try { releaseWrite.await() } catch (_: InterruptedException) {}
        }
        writes.incrementAndGet()
      }
    }
    assertTrue(inWrite.await(2, TimeUnit.SECONDS))
    val stopper = thread(start = true, isDaemon = true) {
      stopAndJoinPlatformOpenHeartbeat(opening, heartbeat)
      stopped.countDown()
    }
    try {
      // An interrupt alone is insufficient while a write is in flight.
      assertFalse(stopped.await(150, TimeUnit.MILLISECONDS))
    } finally {
      releaseWrite.countDown()
    }
    assertTrue(stopped.await(3, TimeUnit.SECONDS))
    stopper.join(3_000)
    assertFalse(heartbeat.isAlive)
    assertEquals(1, writes.get())
  }

  @Test
  fun interruptedJoinCallerStillWaitsAndRetainsInterruptStatus() {
    val opening = AtomicBoolean(true)
    val inWrite = CountDownLatch(1)
    val releaseWrite = CountDownLatch(1)
    val stopped = CountDownLatch(1)
    val wasInterrupted = AtomicBoolean(false)
    val heartbeat = thread(start = true, isDaemon = true) {
      inWrite.countDown()
      while (releaseWrite.count > 0L) {
        try { releaseWrite.await() } catch (_: InterruptedException) {}
      }
    }
    assertTrue(inWrite.await(2, TimeUnit.SECONDS))
    val startedStop = CountDownLatch(1)
    val stopper = thread(start = true, isDaemon = true) {
      startedStop.countDown()
      stopAndJoinPlatformOpenHeartbeat(opening, heartbeat)
      wasInterrupted.set(Thread.currentThread().isInterrupted)
      stopped.countDown()
    }
    try {
      assertTrue(startedStop.await(2, TimeUnit.SECONDS))
      stopper.interrupt()
      assertFalse(stopped.await(150, TimeUnit.MILLISECONDS))
    } finally {
      releaseWrite.countDown()
    }
    assertTrue(stopped.await(3, TimeUnit.SECONDS))
    assertFalse(heartbeat.isAlive)
    assertTrue(wasInterrupted.get())
  }
}
