package me.movenext.flutter_pdf_text

import android.os.ParcelFileDescriptor
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.nio.file.Files
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.rules.TemporaryFolder
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** API35 native snapshot/FD tests; not Android device durability proof. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PlatformSourceSnapshotCustodyTest {
  @get:Rule val folder = TemporaryFolder()

  private fun sha(bytes: ByteArray) = MessageDigest.getInstance("SHA-256")
    .digest(bytes).joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2, '0') }

  private fun bytes(fd: ParcelFileDescriptor): ByteArray =
    ParcelFileDescriptor.AutoCloseInputStream(fd).use { it.readBytes() }

  private fun assertNoSnapshotFiles(cache: File) {
    assertFalse(cache.listFiles().orEmpty().any { it.name.startsWith(".platform-source-custody-") })
  }

  @Test fun verifiedUnlinkedFdSurvivesOriginalPathReplacementAndTruncate() {
    val source = folder.newFile("source.pdf")
    val original = ByteArray(131_072) { (it % 251).toByte() }
    source.writeBytes(original)
    val cache = folder.newFolder("private-cache")
    val custody = PlatformSourceSnapshotCustody.capture(source, cache, original.size.toLong(), sha(original))
    assertEquals(original.size.toLong(), custody.bytes)
    assertEquals(sha(original), custody.sha256)
    assertNoSnapshotFiles(cache)
    source.delete()
    source.writeText("REPLACEMENT")
    RandomAccessFile(source, "rw").use { it.setLength(0) }
    assertArrayEquals(original, bytes(custody.descriptor))
    assertNoSnapshotFiles(cache)
  }

  @Test fun pathnameSwapDuringCopyStillHashesOriginalOpenedFd() {
    val source = folder.newFile("swap.pdf")
    val original = ByteArray(8 * 1024 * 1024 + 8192) { (it % 239).toByte() }
    source.writeBytes(original)
    val cache = folder.newFolder("swap-cache")
    var replaced = false
    val custody = PlatformSourceSnapshotCustody.capture(
      source, cache, original.size.toLong(), sha(original)
    ) { progress ->
      if (!replaced && progress >= 8L * 1024L * 1024L) {
        val moved = folder.root.resolve("original-moved.pdf")
        assertEquals(true, source.renameTo(moved))
        source.writeText("FOREIGN_SOURCE")
        replaced = true
      }
    }
    assertEquals(true, replaced)
    assertArrayEquals(original, bytes(custody.descriptor))
    assertNoSnapshotFiles(cache)
  }

  @Test fun inPlaceTruncateDuringCopyFailsClosed() {
    val source = folder.newFile("truncate.pdf")
    val original = ByteArray(8 * 1024 * 1024 + 8192) { 0x41 }
    source.writeBytes(original)
    val cache = folder.newFolder("truncate-cache")
    assertThrows(IOException::class.java) {
      PlatformSourceSnapshotCustody.capture(source, cache, original.size.toLong(), sha(original)) {
        progress ->
        if (progress >= 8L * 1024L * 1024L) {
          RandomAccessFile(source, "rw").use { it.setLength(0) }
        }
      }
    }
    assertNoSnapshotFiles(cache)
  }

  @Test fun symlinkedSourceFailsClosed() {
    val source = folder.newFile("trusted.pdf")
    source.writeText("TRUSTED")
    val alias = folder.root.toPath().resolve("alias.pdf")
    Files.createSymbolicLink(alias, source.toPath())
    val cache = folder.newFolder("symlink-cache")
    assertThrows(IOException::class.java) {
      PlatformSourceSnapshotCustody.capture(alias.toFile(), cache, 7L, sha("TRUSTED".toByteArray()))
    }
    assertNoSnapshotFiles(cache)
  }

  @Test fun onlyVerifiedSourceShaMismatchMapsToStableExternalFailureCode() {
    assertEquals(
      "PLATFORM_WORKER_SOURCE_SHA256_MISMATCH",
      platformSourceCustodyFailureCode(IOException("SOURCE_CUSTODY_SHA256_MISMATCH"))
    )
    assertEquals(
      "PLATFORM_WORKER_FAILED:IOException",
      platformSourceCustodyFailureCode(IOException("SOURCE_CUSTODY_BYTES_MISMATCH"))
    )
    assertEquals(
      "PLATFORM_WORKER_FAILED:IOException",
      platformSourceCustodyFailureCode(IOException("SOURCE_CUSTODY_SHA256_MISMATCH_FOREIGN"))
    )
  }

  @Test fun incorrectShaAndLengthNeverReturnRendererAuthority() {
    val source = folder.newFile("mismatch.pdf")
    source.writeText("TRUSTED")
    val cache = folder.newFolder("mismatch-cache")
    assertThrows(IOException::class.java) {
      PlatformSourceSnapshotCustody.capture(source, cache, 7L, "0".repeat(64))
    }
    assertNoSnapshotFiles(cache)
    assertThrows(IOException::class.java) {
      PlatformSourceSnapshotCustody.capture(source, cache, 8L, sha("TRUSTED".toByteArray()))
    }
    assertNoSnapshotFiles(cache)
  }

  // C13: a pre-opened same-UID writable FD survives unlink. Terminal progress
  // must run before authoritative hashing; a mutation during that callback
  // must fail closed, never return a mismatched renderer FD. Robolectric only.
  @Test fun terminalProgressWithoutMutationPreservesVerifiedSource() {
    val source = folder.newFile("terminal-progress-clean.pdf")
    val original = ByteArray(128 * 1024 + 1) { (it % 197).toByte() }
    source.writeBytes(original)
    val cache = folder.newFolder("terminal-progress-clean-cache")
    val progress = mutableListOf<Long>()
    val verified = PlatformSourceSnapshotCustody.capture(
      source, cache, original.size.toLong(), sha(original)
    ) { copied -> progress.add(copied) }
    assertEquals(listOf(original.size.toLong()), progress)
    assertEquals(sha(original), verified.sha256)
    assertArrayEquals(original, bytes(verified.descriptor))
    assertNoSnapshotFiles(cache)
  }

  @Test fun terminalProgressWritableFdMutationNeverBecomesVerifiedRendererAuthority() {
    val source = folder.newFile("post-hash-source.pdf")
    val original = ByteArray(8 * 1024 * 1024 + 1024) { (it % 251).toByte() }
    source.writeBytes(original)
    val cache = folder.newFolder("post-hash-cache")
    val expectedSha = sha(original)
    val expectedBytes = original.size.toLong()
    val firstProgress = 8L * 1024L * 1024L
    var heldSnapshot: RandomAccessFile? = null
    var openedBeforeUnlink = false
    var modifiedAtTerminalProgress = false

    var rejectedReason: String? = null
    val verified = try {
      PlatformSourceSnapshotCustody.capture(source, cache, expectedBytes, expectedSha) { copied ->
        if (copied >= firstProgress && copied < expectedBytes && heldSnapshot == null) {
          val named = cache.listFiles().orEmpty().single {
            it.name.startsWith(".platform-source-custody-") && it.name.endsWith(".pdf")
          }
          heldSnapshot = RandomAccessFile(named, "rw")
          openedBeforeUnlink = true
        } else if (copied == expectedBytes && heldSnapshot != null && !modifiedAtTerminalProgress) {
          // Mutate the unlinked inode through the pre-existing writable FD.
          // This callback must precede the final authoritative SHA check.
          val writable = heldSnapshot ?: throw IOException("TEST_SNAPSHOT_FD_MISSING")
          writable.seek(0L)
          writable.writeByte((original[0].toInt() xor 0x7f) and 0xff)
          writable.fd.sync()
          modifiedAtTerminalProgress = true
        }
      }
    } catch (error: IOException) {
      rejectedReason = error.message
      null
    } finally {
      heldSnapshot?.close()
    }

    assertTrue("Test must retain a writable FD before snapshot unlink", openedBeforeUnlink)
    assertTrue("Test must mutate the unlinked inode during terminal progress", modifiedAtTerminalProgress)
    if (verified == null) {
      assertEquals("Mutation must be rejected by the authoritative digest",
        "SOURCE_CUSTODY_SHA256_MISMATCH", rejectedReason)
    } else {
      try {
        // Returning VerifiedSource with a digest for different bytes is RED.
        assertEquals("Renderer FD must match the advertised verified SHA", expectedSha,
          sha(bytes(verified.descriptor)))
      } finally {
        verified.descriptor.close()
      }
    }
    assertNoSnapshotFiles(cache)
  }
}
