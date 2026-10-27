package me.movenext.flutter_pdf_text

import android.os.ParcelFileDescriptor
import java.io.File
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.StandardOpenOption
import java.nio.file.attribute.FileTime
import java.security.MessageDigest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.rules.TemporaryFolder
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** API35 JVM orphan scavenging, not independent process-death durability proof. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PlatformSourceSnapshotOrphanCleanupTest {
  @get:Rule val folder = TemporaryFolder()
  private val hour = 60L * 60L * 1000L
  private val now = 1_800_000_000_000L

  private fun orphan(cache: File, suffix: String): File =
    File(cache, ".platform-source-custody-$suffix.pdf").apply { writeText("orphan") }

  private fun age(file: File) {
    Files.setLastModifiedTime(file.toPath(), FileTime.fromMillis(now - 25L * hour))
  }

  @Test fun staleUnlockedOrphanIsRemovedButFreshAndUnrelatedFilesRemain() {
    val cache = folder.newFolder("cache")
    val stale = orphan(cache, "stale")
    val fresh = orphan(cache, "fresh")
    val unrelated = File(cache, "important.pdf").apply { writeText("keep") }
    age(stale)
    age(unrelated)
    assertEquals(1, PlatformSourceSnapshotCustody.pruneStaleOrphans(cache, now))
    assertFalse(stale.exists())
    assertTrue(fresh.exists())
    assertEquals("keep", unrelated.readText())
  }

  @Test fun heldLockPreventsDeletionEvenWhenSnapshotIsOld() {
    val cache = folder.newFolder("locked-cache")
    val active = orphan(cache, "active")
    age(active)
    FileChannel.open(active.toPath(), StandardOpenOption.WRITE).use { channel ->
      val held = channel.lock()
      try {
        assertEquals(0, PlatformSourceSnapshotCustody.pruneStaleOrphans(cache, now))
        assertTrue(active.exists())
      } finally {
        held.release()
      }
    }
    assertEquals(1, PlatformSourceSnapshotCustody.pruneStaleOrphans(cache, now))
    assertFalse(active.exists())
  }

  @Test fun symlinkWithSnapshotNameNeverDeletesItsExternalTarget() {
    val cache = folder.newFolder("link-cache")
    val outside = folder.newFile("outside.pdf").apply { writeText("protected") }
    val link = File(cache, ".platform-source-custody-link.pdf").toPath()
    Files.createSymbolicLink(link, outside.toPath())
    assertEquals(0, PlatformSourceSnapshotCustody.pruneStaleOrphans(cache, now))
    assertTrue(Files.isSymbolicLink(link))
    assertEquals("protected", outside.readText())
  }

  @Test fun captureScavengesOldOrphanAndKeepsVerifiedUnlinkedFd() {
    val cache = folder.newFolder("capture-cache")
    val stale = orphan(cache, "crash-leftover")
    Files.setLastModifiedTime(
      stale.toPath(), FileTime.fromMillis(System.currentTimeMillis() - 25L * hour))
    val source = folder.newFile("source.pdf").apply { writeText("TRUSTED") }
    val sha = MessageDigest.getInstance("SHA-256").digest("TRUSTED".toByteArray())
      .joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2, '0') }
    val verified = PlatformSourceSnapshotCustody.capture(source, cache, 7L, sha)
    assertFalse(stale.exists())
    assertEquals(7L, verified.bytes)
    ParcelFileDescriptor.AutoCloseInputStream(verified.descriptor).use { input ->
      assertEquals("TRUSTED", String(input.readBytes(), Charsets.UTF_8))
    }
    assertFalse(cache.listFiles().orEmpty().any {
      it.name.startsWith(".platform-source-custody-")
    })
  }
}
