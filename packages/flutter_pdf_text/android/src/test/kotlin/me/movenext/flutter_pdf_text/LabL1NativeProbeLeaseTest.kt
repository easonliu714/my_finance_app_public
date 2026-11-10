package me.movenext.flutter_pdf_text

import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LabL1NativeProbeLeaseTest {
  @Test fun overlappingStartDoesNotAdmitOrReleaseIncumbent() {
    val lease = LabL1NativeProbeLease()
    lease.noteStart(1)
    assertTrue(lease.tryAcquire())
    lease.noteStart(2)
    assertFalse(lease.tryAcquire())
    assertTrue(lease.isActive())
    assertEquals(2, lease.latestStartId())
    assertFalse(lease.tryAcquire())
  }

  @Test fun rejectedAndNullStartsAdvanceTerminalStopId() {
    val lease = LabL1NativeProbeLease()
    lease.noteStart(11)
    assertTrue(lease.tryAcquire())
    lease.noteStart(12)
    assertFalse(lease.tryAcquire())
    lease.noteStart(13)
    assertEquals(13, lease.latestStartId())
    lease.release()
    assertFalse(lease.isActive())
  }

  @Test fun releasePermitsNextIndependentWorker() {
    val lease = LabL1NativeProbeLease()
    lease.noteStart(1)
    assertTrue(lease.tryAcquire())
    lease.release()
    lease.noteStart(2)
    assertTrue(lease.tryAcquire())
    assertEquals(2, lease.latestStartId())
    lease.release()
  }

  @Test fun sixteenSimultaneousAttemptsAdmitExactlyOne() {
    val lease = LabL1NativeProbeLease()
    val gate = CountDownLatch(1)
    val finished = CountDownLatch(16)
    val admitted = AtomicInteger(0)
    val workers = (1..16).map {
      thread(start = true) {
        try {
          gate.await()
          if (lease.tryAcquire()) admitted.incrementAndGet()
        } finally {
          finished.countDown()
        }
      }
    }
    gate.countDown()
    finished.await()
    workers.forEach { it.join() }
    assertEquals(1, admitted.get())
    assertTrue(lease.isActive())
    lease.release()
  }
}
