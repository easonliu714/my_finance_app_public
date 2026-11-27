package me.movenext.flutter_pdf_text

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
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

  @Test fun terminalPublishedOnlyAfterStopAndRelease() {
    val lease = LabL1NativeProbeLease()
    lease.noteStart(1)
    assertTrue(lease.tryAcquire())
    lease.noteStart(2)
    val events = mutableListOf<String>()
    lease.finish(stop = {
      assertEquals(2, it)
      assertTrue(lease.isActive())
      events.add("stop")
    }, publishTerminal = {
      assertFalse(lease.isActive())
      events.add("terminal")
    })
    assertEquals(listOf("stop", "terminal"), events)
    assertTrue(lease.tryAcquire())
    lease.release()
  }

  @Test fun admissionCannotOvertakeTerminalPublication() {
    val lease = LabL1NativeProbeLease()
    lease.noteStart(1)
    assertTrue(lease.tryAcquire())
    val publishing = CountDownLatch(1)
    val allowPublish = CountDownLatch(1)
    val attempting = CountDownLatch(1)
    val admitted = CountDownLatch(1)
    val finish = thread {
      lease.finish(stop = {}, publishTerminal = {
        publishing.countDown()
        check(allowPublish.await(5, TimeUnit.SECONDS))
      })
    }
    var next: Thread? = null
    try {
      assertTrue(publishing.await(5, TimeUnit.SECONDS))
      next = thread {
        attempting.countDown()
        if (lease.tryAcquire()) admitted.countDown()
      }
      assertTrue(attempting.await(5, TimeUnit.SECONDS))
      assertFalse(admitted.await(100, TimeUnit.MILLISECONDS))
    } finally {
      allowPublish.countDown()
      finish.join(5000)
      next?.join(5000)
    }
    assertFalse(finish.isAlive)
    assertTrue(next?.isAlive == false)
    assertEquals(0L, admitted.count)
    lease.release()
  }

  @Test fun failedStopDoesNotPublishTerminal() {
    val lease = LabL1NativeProbeLease()
    assertTrue(lease.tryAcquire())
    var published = false
    var failed = false
    try {
      lease.finish(stop = { error("stop failed") },
        publishTerminal = { published = true })
    } catch (_: IllegalStateException) {
      failed = true
    }
    assertTrue(failed)
    assertFalse(published)
    assertFalse(lease.isActive())
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
