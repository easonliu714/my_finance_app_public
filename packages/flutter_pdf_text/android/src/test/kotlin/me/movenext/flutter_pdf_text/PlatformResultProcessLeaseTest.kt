package me.movenext.flutter_pdf_text

import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.StandardCopyOption
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** JVM OS-lock contract, not Android device or process-death proof. */
class PlatformResultProcessLeaseTest {
  @get:Rule val folder = TemporaryFolder()

  @Test fun sameResultCannotBeOwnedTwiceUntilLockReleased() {
    val result = folder.newFile("same.json")
    val first = PlatformResultProcessLease.tryAcquire(result.path)
    assertNotNull(first)
    try { assertNull(PlatformResultProcessLease.tryAcquire(result.path)) }
    finally { first!!.close() }
    val second = PlatformResultProcessLease.tryAcquire(result.path)
    assertNotNull(second)
    second!!.close()
  }

  @Test fun differentResultsUseIndependentSidecars() {
    val dir = folder.newFolder("independent")
    val a = PlatformResultProcessLease.tryAcquire(dir.resolve("a.json").path)
    val b = PlatformResultProcessLease.tryAcquire(dir.resolve("b.json").path)
    assertNotNull(a)
    assertNotNull(b)
    try {
      assertNull(PlatformResultProcessLease.tryAcquire(dir.resolve("a.json").path))
      assertNull(PlatformResultProcessLease.tryAcquire(dir.resolve("b.json").path))
    } finally { a!!.close(); b!!.close() }
  }

  @Test fun missingParentAndSymlinkedLockFailClosed() {
    val dir = folder.newFolder("unsafe")
    assertNull(PlatformResultProcessLease.tryAcquire(
      dir.resolve("missing").resolve("result.json").path))
    val sidecar = dir.toPath().resolve(".result.json.platform-worker.lock")
    Files.createSymbolicLink(sidecar, dir.toPath().resolve("untrusted"))
    assertNull(PlatformResultProcessLease.tryAcquire(dir.resolve("result.json").path))
    assertTrue(Files.isSymbolicLink(sidecar))
  }

  @Test fun cleanupFailureReleasesKernelLockButCannotReopenService() {
    val result = folder.newFile("cleanup.json")
    val lease = PlatformWorkerStartLease()
    val owner = lease.acquire(1, "request-A", result.path)
    assertNotNull(owner)
    assertNull(PlatformResultProcessLease.tryAcquire(result.path))
    assertThrows(IllegalStateException::class.java) {
      lease.finish(owner!!) { throw IllegalStateException("INJECTED_STOP_FAILURE") }
    }
    assertFalse(lease.isActive())
    assertNull(lease.acquire(2, "request-B", result.path))
    val recovered = PlatformResultProcessLease.tryAcquire(result.path)
    assertNotNull(recovered)
    recovered!!.close()
  }

  @Test fun sidecarRenameDuringAcquisitionRejectsStaleInode() {
    val result = folder.newFile("replace-during-lock.json")
    val initial = PlatformResultProcessLease.tryAcquire(result.path)
    assertNotNull(initial)
    initial!!.close()
    val sidecar = folder.root.toPath().resolve(
      ".replace-during-lock.json.platform-worker.lock")
    val replacement = folder.newFile("replacement-lock-inode").toPath()
    assertNull(PlatformResultProcessLease.tryAcquire(result.path) {
      Files.move(replacement, sidecar,
        StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
    })
    assertTrue(Files.isRegularFile(sidecar, LinkOption.NOFOLLOW_LINKS))
    val recovered = PlatformResultProcessLease.tryAcquire(result.path)
    assertNotNull(recovered)
    recovered!!.close()
  }

  @Test fun sidecarSymlinkSwapDuringAcquisitionFailsClosed() {
    val result = folder.newFile("symlink-during-lock.json")
    val initial = PlatformResultProcessLease.tryAcquire(result.path)
    assertNotNull(initial)
    initial!!.close()
    val sidecar = folder.root.toPath().resolve(
      ".symlink-during-lock.json.platform-worker.lock")
    val foreign = folder.newFile("foreign-lock").toPath()
    assertNull(PlatformResultProcessLease.tryAcquire(result.path) {
      Files.delete(sidecar)
      Files.createSymbolicLink(sidecar, foreign)
    })
    assertTrue(Files.isSymbolicLink(sidecar))
    Files.delete(sidecar)
    val recovered = PlatformResultProcessLease.tryAcquire(result.path)
    assertNotNull(recovered)
    recovered!!.close()
  }

  @Test fun unchangedSidecarPassesInodeCheckAndRemainsExclusive() {
    val result = folder.newFile("stable-during-lock.json")
    val lease = PlatformResultProcessLease.tryAcquire(result.path) {
      assertTrue(Files.isRegularFile(
        folder.root.toPath().resolve(".stable-during-lock.json.platform-worker.lock"),
        LinkOption.NOFOLLOW_LINKS))
    }
    assertNotNull(lease)
    try { assertNull(PlatformResultProcessLease.tryAcquire(result.path)) }
    finally { lease!!.close() }
  }
}
