package me.movenext.flutter_pdf_text

import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Small synthetic bytes only, never a real official PDF or full10 verdict. */
class LabL1VerifiedPdfSnapshotTest {
  private val role = LabL1MayJuneDualPdfOracle.Role.SORTED

  private fun sha(bytes: ByteArray): String =
    MessageDigest.getInstance("SHA-256").digest(bytes)
      .joinToString("") { "%02x".format(it.toInt() and 255) }

  private fun rejected(block: () -> Unit) {
    try {
      block()
      fail("expected fail-closed snapshot rejection")
    } catch (_: IllegalStateException) {
      // Expected; never promotes unverified content into a renderer session.
    }
  }

  @Test fun retainsVerifiedCopyAfterOriginalMutationAndPathReplacement() {
    val base = Files.createTempDirectory("l1-snapshot-test-").toFile()
    try {
      val files = File(base, "files").apply { mkdirs() }
      val cache = File(base, "cache").apply { mkdirs() }
      val original = File(files, "owner.pdf")
      val payload = "%PDF-1.4\nsynthetic-safe-content\n%%EOF".toByteArray()
      original.writeBytes(payload)
      val expected = LabL1VerifiedPdfSnapshot.Expected(role, payload.size.toLong(), sha(payload))
      LabL1VerifiedPdfSnapshot.openVerified(original, files, cache, expected).use { snapshot ->
        assertEquals(role, snapshot.role)
        assertEquals(expected.sha256, snapshot.sha256)
        assertEquals(payload.size.toLong(), snapshot.bytes)
        assertTrue("snapshot must be unlinked before Pdfium handoff",
          cache.listFiles().orEmpty().isEmpty())
        original.writeBytes("changed content at the source".toByteArray())
        assertTrue(original.delete())
        original.writeBytes("replaced mutable path".toByteArray())
        snapshot.readOnlyFile.seek(0)
        val copied = ByteArray(payload.size)
        snapshot.readOnlyFile.readFully(copied)
        assertArrayEquals(payload, copied)
      }
      assertTrue(cache.listFiles().orEmpty().isEmpty())
    } finally { base.deleteRecursively() }
  }

  @Test fun wrongRoleHashAndSameLengthTamperingLeaveNoSnapshot() {
    val base = Files.createTempDirectory("l1-snapshot-negative-").toFile()
    try {
      val files = File(base, "files").apply { mkdirs() }
      val cache = File(base, "cache").apply { mkdirs() }
      val original = File(files, "owner.pdf")
      val payload = "%PDF-owner-role-synthetic".toByteArray()
      original.writeBytes(payload)
      val correct = LabL1VerifiedPdfSnapshot.Expected(role, payload.size.toLong(), sha(payload))
      val wrongRoleDigest = LabL1VerifiedPdfSnapshot.Expected(
        LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER, correct.bytes, sha("different role".toByteArray()))
      rejected { LabL1VerifiedPdfSnapshot.openVerified(original, files, cache, wrongRoleDigest).close() }
      assertTrue(cache.listFiles().orEmpty().isEmpty())
      val changed = payload.copyOf().apply { this[2] = (this[2] + 1).toByte() }
      original.writeBytes(changed)
      rejected { LabL1VerifiedPdfSnapshot.openVerified(original, files, cache, correct).close() }
      assertTrue(cache.listFiles().orEmpty().isEmpty())
      original.writeBytes(payload.copyOfRange(0, payload.size - 1))
      rejected { LabL1VerifiedPdfSnapshot.openVerified(original, files, cache, correct).close() }
      assertTrue(cache.listFiles().orEmpty().isEmpty())
    } finally { base.deleteRecursively() }
  }

  @Test fun outsideFilesRootMissingFileAndInvalidManifestFailClosed() {
    val base = Files.createTempDirectory("l1-snapshot-root-").toFile()
    try {
      val files = File(base, "files").apply { mkdirs() }
      val cache = File(base, "cache").apply { mkdirs() }
      val external = File(base, "external.pdf")
      val payload = "%PDF-owner-source-guard".toByteArray()
      external.writeBytes(payload)
      val expected = LabL1VerifiedPdfSnapshot.Expected(role, payload.size.toLong(), sha(payload))
      rejected { LabL1VerifiedPdfSnapshot.openVerified(external, files, cache, expected).close() }
      rejected { LabL1VerifiedPdfSnapshot.openVerified(File(files, "missing.pdf"), files, cache, expected).close() }
      external.copyTo(File(files, "present.pdf"))
      val invalid = expected.copy(sha256 = "not-a-sha")
      rejected { LabL1VerifiedPdfSnapshot.openVerified(File(files, "present.pdf"), files, cache, invalid).close() }
      assertFalse(cache.listFiles().orEmpty().any())
      assertEquals(119769589L,
        LabL1MayJuneOwnerAttestedBytePair.pinnedRole(role).first)
      assertEquals(146461156L,
        LabL1MayJuneOwnerAttestedBytePair.pinnedRole(
          LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER).first)
    } finally { base.deleteRecursively() }
  }
}
