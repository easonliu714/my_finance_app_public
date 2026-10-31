package me.movenext.flutter_pdf_text

import java.io.Closeable
import java.io.File
import java.io.IOException
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** API35 JVM result-parent no-follow boundary, not same-UID swap proof. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PlatformResultParentCustodyTest {
  @get:Rule val folder = TemporaryFolder()

  // JVM/Robolectric filesystem-boundary tests inject a synthetic binder;
  // real Android LocalServerSocket ownership is exercised by API35 instrumentation.
  private val boundNames = mutableSetOf<String>()
  private fun bindFakeKernel(name: String): Closeable? = synchronized(boundNames) {
    if (!boundNames.add(name)) null else Closeable {
      synchronized(boundNames) { boundNames.remove(name) }
    }
  }
  private fun tryAcquire(path: String) =
    PlatformResultProcessLease.tryAcquireWithKernelFenceForTest(
      path, bindKernel = ::bindFakeKernel)

  @Test fun symlinkedParentCannotRedirectResultOrLease() {
    val outside = folder.newFolder("outside")
    val alias = folder.root.toPath().resolve("alias")
    Files.createSymbolicLink(alias, outside.toPath())
    val result = alias.resolve("result.json")
    assertNull(tryAcquire(result.toString()))
    val writer = PlatformResultAtomicWriter(syncParent = {})
    val error = assertThrows(IOException::class.java) {
      writer.write(result.toString(), """{"request_id":"A","status":"running"}""")
    }
    assertEquals("RESULT_PARENT_UNTRUSTED", error.message)
    assertFalse(File(outside, "result.json").exists())
    assertFalse(File(outside, ".result.json.platform-worker.lock").exists())
    assertTrue(Files.isSymbolicLink(alias))
  }

  @Test fun ordinaryFileCannotBeUsedAsResultParent() {
    val notDirectory = folder.newFile("not-a-directory").apply { writeText("keep") }
    val result = File(notDirectory, "result.json")
    assertNull(tryAcquire(result.path))
    assertThrows(IOException::class.java) {
      PlatformResultAtomicWriter(syncParent = {}).write(
        result.path, """{"request_id":"A","status":"running"}""")
    }
    assertEquals("keep", notDirectory.readText())
  }

  @Test fun realParentRetainsExclusiveLeaseAndValidRunningWrite() {
    val parent = folder.newFolder("real")
    val result = File(parent, "result.json")
    val first = tryAcquire(result.path)
    assertNotNull(first)
    try {
      assertNull(tryAcquire(result.path))
      PlatformResultAtomicWriter(syncParent = {}).write(
        result.path, """{"request_id":"A","status":"running"}""")
      assertTrue(result.readText().contains(""""status":"running""""))
    } finally {
      first!!.close()
    }
    val reacquired = tryAcquire(result.path)
    assertNotNull(reacquired)
    reacquired!!.close()
  }

  @Test fun writerMayCreateNewOrdinaryParentBeforeLeaseAcquisition() {
    val parent = File(folder.root, "new-safe-parent")
    val result = File(parent, "result.json")
    PlatformResultAtomicWriter(syncParent = {}).write(
      result.path, """{"request_id":"B","status":"running"}""")
    assertTrue(result.isFile)
    val lease = tryAcquire(result.path)
    assertNotNull(lease)
    lease!!.close()
  }
}
