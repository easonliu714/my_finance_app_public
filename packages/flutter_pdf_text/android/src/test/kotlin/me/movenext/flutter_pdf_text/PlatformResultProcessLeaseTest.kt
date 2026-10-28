package me.movenext.flutter_pdf_text

import java.io.Closeable
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

  // Synthetic JVM binder: real Android kernel behavior is instrumented separately.
  private val boundNames = mutableSetOf<String>()
  private fun bindFakeKernel(name: String): Closeable? = synchronized(boundNames) {
    if (!boundNames.add(name)) null else Closeable {
      synchronized(boundNames) { boundNames.remove(name) }
    }
  }
  private fun tryAcquire(path: String, afterOpenBeforeLock: (() -> Unit)? = null) =
    PlatformResultProcessLease.tryAcquireWithKernelFenceForTest(
      path, afterOpenBeforeLock, ::bindFakeKernel)

  @Test fun sameResultCannotBeOwnedTwiceUntilLockReleased() {
    val result = folder.newFile("same.json")
    val first = tryAcquire(result.path)
    assertNotNull(first)
    try { assertNull(tryAcquire(result.path)) }
    finally { first!!.close() }
    val second = tryAcquire(result.path)
    assertNotNull(second)
    second!!.close()
  }

  @Test fun differentResultsUseIndependentSidecars() {
    val dir = folder.newFolder("independent")
    val a = tryAcquire(dir.resolve("a.json").path)
    val b = tryAcquire(dir.resolve("b.json").path)
    assertNotNull(a)
    assertNotNull(b)
    try {
      assertNull(tryAcquire(dir.resolve("a.json").path))
      assertNull(tryAcquire(dir.resolve("b.json").path))
    } finally { a!!.close(); b!!.close() }
  }

  @Test fun missingParentAndSymlinkedLockFailClosed() {
    val dir = folder.newFolder("unsafe")
    assertNull(tryAcquire(
      dir.resolve("missing").resolve("result.json").path))
    val sidecar = dir.toPath().resolve(".result.json.platform-worker.lock")
    Files.createSymbolicLink(sidecar, dir.toPath().resolve("untrusted"))
    assertNull(tryAcquire(dir.resolve("result.json").path))
    assertTrue(Files.isSymbolicLink(sidecar))
  }

  @Test fun cleanupFailureReleasesKernelLockButCannotReopenService() {
    val result = folder.newFile("cleanup.json")
    val lease = PlatformWorkerStartLease(acquireProcessLease = { tryAcquire(it) })
    val owner = lease.acquire(1, "request-A", result.path)
    assertNotNull(owner)
    assertNull(tryAcquire(result.path))
    assertThrows(IllegalStateException::class.java) {
      lease.finish(owner!!) { throw IllegalStateException("INJECTED_STOP_FAILURE") }
    }
    assertFalse(lease.isActive())
    assertNull(lease.acquire(2, "request-B", result.path))
    val recovered = tryAcquire(result.path)
    assertNotNull(recovered)
    recovered!!.close()
  }

  @Test fun sidecarRenameDuringAcquisitionRejectsStaleInode() {
    val result = folder.newFile("replace-during-lock.json")
    val initial = tryAcquire(result.path)
    assertNotNull(initial)
    initial!!.close()
    val sidecar = folder.root.toPath().resolve(
      ".replace-during-lock.json.platform-worker.lock")
    val replacement = folder.newFile("replacement-lock-inode").toPath()
    assertNull(tryAcquire(result.path) {
      Files.move(replacement, sidecar,
        StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
    })
    assertTrue(Files.isRegularFile(sidecar, LinkOption.NOFOLLOW_LINKS))
    val recovered = tryAcquire(result.path)
    assertNotNull(recovered)
    recovered!!.close()
  }

  @Test fun sidecarSymlinkSwapDuringAcquisitionFailsClosed() {
    val result = folder.newFile("symlink-during-lock.json")
    val initial = tryAcquire(result.path)
    assertNotNull(initial)
    initial!!.close()
    val sidecar = folder.root.toPath().resolve(
      ".symlink-during-lock.json.platform-worker.lock")
    val foreign = folder.newFile("foreign-lock").toPath()
    assertNull(tryAcquire(result.path) {
      Files.delete(sidecar)
      Files.createSymbolicLink(sidecar, foreign)
    })
    assertTrue(Files.isSymbolicLink(sidecar))
    Files.delete(sidecar)
    val recovered = tryAcquire(result.path)
    assertNotNull(recovered)
    recovered!!.close()
  }

  @Test fun unchangedSidecarPassesInodeCheckAndRemainsExclusive() {
    val result = folder.newFile("stable-during-lock.json")
    val lease = tryAcquire(result.path) {
      assertTrue(Files.isRegularFile(
        folder.root.toPath().resolve(".stable-during-lock.json.platform-worker.lock"),
        LinkOption.NOFOLLOW_LINKS))
    }
    assertNotNull(lease)
    try { assertNull(tryAcquire(result.path)) }
    finally { lease!!.close() }
  }

  @Test fun heldSidecarRenameAndReplacementCannotReenterSameProcess() {
    val result = folder.newFile("held-replaced.json")
    val first = tryAcquire(result.path)
    assertNotNull(first)
    val sidecar = folder.root.toPath().resolve(
      ".held-replaced.json.platform-worker.lock")
    val displaced = folder.root.toPath().resolve("held-original-inode.lock")
    try {
      // The original kernel lock remains on the displaced inode.
      Files.move(sidecar, displaced, StandardCopyOption.ATOMIC_MOVE)
      Files.createFile(sidecar)
      assertTrue(Files.isRegularFile(sidecar, LinkOption.NOFOLLOW_LINKS))
      assertNull(tryAcquire(result.path))
    } finally { first!!.close() }
    val recovered = tryAcquire(result.path)
    assertNotNull(recovered)
    recovered!!.close()
  }

  @Test fun heldSidecarUnlinkCannotReenterSameProcess() {
    val result = folder.newFile("held-unlinked.json")
    val first = tryAcquire(result.path)
    assertNotNull(first)
    val sidecar = folder.root.toPath().resolve(
      ".held-unlinked.json.platform-worker.lock")
    try {
      Files.delete(sidecar)
      assertFalse(Files.exists(sidecar, LinkOption.NOFOLLOW_LINKS))
      assertNull(tryAcquire(result.path))
    } finally { first!!.close() }
    val recovered = tryAcquire(result.path)
    assertNotNull(recovered)
    recovered!!.close()
  }

  @Test fun failedAcquisitionDoesNotLeakProcessReservation() {
    val result = folder.newFile("rejected-reservation.json")
    val sidecar = folder.root.toPath().resolve(
      ".rejected-reservation.json.platform-worker.lock")
    Files.createSymbolicLink(sidecar, folder.newFile("untrusted-sidecar").toPath())
    assertNull(tryAcquire(result.path))
    Files.delete(sidecar)
    val recovered = tryAcquire(result.path)
    assertNotNull(recovered)
    recovered!!.close()
  }

  @Test fun abstractKernelBindFailureNeverFallsBackToReplaceableSidecar() {
    val result = folder.newFile("bind-fail.json")
    val denied = PlatformResultProcessLease.tryAcquireWithKernelFenceForTest(
      result.path, bindKernel = { null })
    assertNull(denied)
    assertFalse(Files.exists(folder.root.toPath().resolve(
      ".bind-fail.json.platform-worker.lock"), LinkOption.NOFOLLOW_LINKS))
    val recovered = tryAcquire(result.path)
    assertNotNull(recovered)
    recovered!!.close()
  }

  @Test fun ancestorSymlinkAliasCannotAcquireSecondLogicalResult() {
    val root = folder.newFolder("canonical-root").toPath()
    val actualParent = Files.createDirectory(root.resolve("nested"))
    val alias = root.resolve("ancestor-alias")
    Files.createSymbolicLink(alias, root)
    val realResult = actualParent.resolve("result.json")
    val aliasResult = alias.resolve("nested").resolve("result.json")
    val first = tryAcquire(realResult.toString())
    assertNotNull(first)
    try { assertNull(tryAcquire(aliasResult.toString())) }
    finally { first!!.close() }
    val recovered = tryAcquire(aliasResult.toString())
    assertNotNull(recovered)
    recovered!!.close()
  }

  @Test fun repeatedCloseCannotReleaseNewOwnersReservation() {
    val result = folder.newFile("idempotent-close.json")
    val first = tryAcquire(result.path)
    assertNotNull(first)
    first!!.close()
    val second = tryAcquire(result.path)
    assertNotNull(second)
    try {
      first.close()
      assertNull(tryAcquire(result.path))
    } finally { second!!.close() }
  }
}
