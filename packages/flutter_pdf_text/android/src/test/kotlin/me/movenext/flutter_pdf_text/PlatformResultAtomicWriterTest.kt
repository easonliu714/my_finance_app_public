package me.movenext.flutter_pdf_text

import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Synthetic JVM positive/negative native writer tests; not Android device evidence. */
class PlatformResultAtomicWriterTest {
  @get:Rule val folder = TemporaryFolder()

  @Test fun uniqueSameDirectoryTempsAndReplace() {
    val dir = folder.newFolder("replace")
    val target = dir.resolve("result.json")
    target.writeText("previous")
    val names = mutableListOf<String>()
    val syncs = AtomicInteger()
    val writer = PlatformResultAtomicWriter(
      atomicReplace = { tmp, dst ->
        assertEquals(dir.canonicalPath, tmp.parent.toFile().canonicalPath)
        names.add(tmp.fileName.toString())
        Files.move(tmp, dst, StandardCopyOption.ATOMIC_MOVE,
          StandardCopyOption.REPLACE_EXISTING)
      },
      syncParent = { parent ->
        assertEquals(dir.canonicalPath, parent.toFile().canonicalPath)
        syncs.incrementAndGet()
      })
    writer.write(target.path, "first")
    writer.write(target.path, "second")
    assertEquals("second", target.readText())
    assertEquals(2, names.toSet().size)
    assertEquals(2, syncs.get())
    assertFalse(dir.listFiles().orEmpty().any { it.name.endsWith(".tmp") })
  }

  @Test fun injectedRenameFailurePreservesTrustedTarget() {
    val dir = folder.newFolder("rename")
    val target = dir.resolve("result.json")
    target.writeText("trusted")
    val syncs = AtomicInteger()
    val writer = PlatformResultAtomicWriter(
      atomicReplace = { _, _ -> throw IOException("INJECTED_RENAME_FAILURE") },
      syncParent = { syncs.incrementAndGet() })
    assertThrows(IOException::class.java) { writer.write(target.path, "untrusted") }
    assertEquals("trusted", target.readText())
    assertEquals(0, syncs.get())
    assertFalse(dir.listFiles().orEmpty().any { it.name.endsWith(".tmp") })
  }

  @Test fun directorySyncFailurePropagatesWithoutSuccessClaim() {
    val dir = folder.newFolder("sync")
    val target = dir.resolve("result.json")
    val writer = PlatformResultAtomicWriter(
      syncParent = { throw IOException("INJECTED_PARENT_FSYNC_FAILURE") })
    assertThrows(IOException::class.java) { writer.write(target.path, "unverified") }
    // A rename may already have occurred; durability is NOT proven.
    assertFalse(dir.listFiles().orEmpty().any { it.name.endsWith(".tmp") })
  }

  @Test fun concurrentCallsOnOneWriterAreSerialized() {
    val dir = folder.newFolder("serial")
    val target = dir.resolve("result.json")
    val entered = CountDownLatch(1)
    val release = CountDownLatch(1)
    val active = AtomicInteger()
    val peak = AtomicInteger()
    val writer = PlatformResultAtomicWriter(
      atomicReplace = { tmp, dst ->
        val current = active.incrementAndGet()
        peak.updateAndGet { old -> maxOf(old, current) }
        try {
          entered.countDown()
          assertTrue(release.await(5, TimeUnit.SECONDS))
          Files.move(tmp, dst, StandardCopyOption.ATOMIC_MOVE,
            StandardCopyOption.REPLACE_EXISTING)
        } finally { active.decrementAndGet() }
      },
      syncParent = {})
    val pool = Executors.newFixedThreadPool(2)
    try {
      val first = pool.submit { writer.write(target.path, "first") }
      assertTrue(entered.await(3, TimeUnit.SECONDS))
      val second = pool.submit { writer.write(target.path, "second") }
      release.countDown()
      first.get(5, TimeUnit.SECONDS)
      second.get(5, TimeUnit.SECONDS)
      assertEquals(1, peak.get())
      assertTrue(target.readText() in setOf("first", "second"))
      assertFalse(dir.listFiles().orEmpty().any { it.name.endsWith(".tmp") })
    } finally {
      release.countDown()
      pool.shutdownNow()
    }
  }
}
