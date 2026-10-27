package me.movenext.flutter_pdf_text

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/** Synthetic JVM concurrency contract; no Android device or cross-process proof. */
class PlatformWorkerStartLeaseTest {
  @Test fun overlappingDifferentRequestAndDuplicateStartCannotOwnForeground() {
    val lease = PlatformWorkerStartLease()
    val first = lease.acquire(11, "request-A", "/synthetic/result-A.json")!!
    assertEquals(11, first.startId)
    assertEquals("request-A", first.requestId)
    assertTrue(lease.isActive())
    assertNull(lease.acquire(12, "request-B", "/synthetic/result-A.json"))
    assertNull(lease.acquire(11, "request-A", "/synthetic/result-A.json"))
    var cleanupCalls = 0
    assertTrue(lease.finish(first) { cleanupCalls++ })
    assertEquals(1, cleanupCalls)
    assertFalse(lease.isActive())
    assertNull(lease.acquire(13, "request-C", "/synthetic/result-C.json"))
  }

  @Test fun forgedOrStaleTokenCannotStopTheActualOwner() {
    val lease = PlatformWorkerStartLease()
    val owner = lease.acquire(21, "owner", "/synthetic/owner.json")!!
    val other = PlatformWorkerStartLease().acquire(21, "owner", "/synthetic/owner.json")!!
    var stopCount = 0
    assertFalse(lease.finish(other) { stopCount++ })
    assertEquals(0, stopCount)
    assertTrue(lease.isActive())
    assertTrue(lease.finish(owner) { stopCount++ })
    assertFalse(lease.finish(owner) { stopCount++ })
    assertEquals(1, stopCount)
  }

  @Test fun cleanupCannotRaceASecondStartIntoForeground() {
    val lease = PlatformWorkerStartLease()
    val owner = lease.acquire(31, "owner", "/synthetic/owner.json")!!
    val inCleanup = CountDownLatch(1)
    val releaseCleanup = CountDownLatch(1)
    val contenderStarted = CountDownLatch(1)
    val pool = Executors.newFixedThreadPool(2)
    try {
      val finish = pool.submit<Boolean> {
        lease.finish(owner) {
          inCleanup.countDown()
          assertTrue(releaseCleanup.await(5, TimeUnit.SECONDS))
        }
      }
      assertTrue(inCleanup.await(3, TimeUnit.SECONDS))
      val contender = pool.submit<PlatformWorkerStartLease.Token?> {
        contenderStarted.countDown()
        lease.acquire(32, "other", "/synthetic/other.json")
      }
      assertTrue(contenderStarted.await(3, TimeUnit.SECONDS))
      assertThrows(TimeoutException::class.java) {
        contender.get(150, TimeUnit.MILLISECONDS)
      }
      releaseCleanup.countDown()
      assertTrue(finish.get(5, TimeUnit.SECONDS))
      assertNull(contender.get(5, TimeUnit.SECONDS))
    } finally {
      releaseCleanup.countDown()
      pool.shutdownNow()
    }
  }

  @Test fun failedCleanupCannotReopenServiceOwnership() {
    val lease = PlatformWorkerStartLease()
    assertNull(lease.acquire(0, "invalid", "/synthetic/x.json"))
    assertNull(lease.acquire(41, "", "/synthetic/x.json"))
    assertNull(lease.acquire(41, "owner", ""))
    val owner = lease.acquire(41, "owner", "/synthetic/x.json")!!
    assertThrows(IllegalStateException::class.java) {
      lease.finish(owner) { throw IllegalStateException("INJECTED_FOREGROUND_STOP_FAILURE") }
    }
    assertFalse(lease.isActive())
    assertNull(lease.acquire(42, "other", "/synthetic/other.json"))
  }
}
