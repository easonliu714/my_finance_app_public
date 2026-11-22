package me.movenext.flutter_pdf_text

import java.io.File
import java.security.MessageDigest
import kotlin.io.path.createTempDirectory
import org.junit.Assert.*
import org.junit.Test

class PdfiumWorkerVerifiedSnapshotTest {
  private fun sha(bytes: ByteArray) = MessageDigest.getInstance("SHA-256")
    .digest(bytes).joinToString("") { (it.toInt() and 255).toString(16).padStart(2, '0') }

  @Test fun verifiedUnlinkedDescriptorSurvivesPathReplacement() {
    val root = createTempDirectory("worker-snapshot-").toFile()
    try {
      val source = File(root, "official.pdf")
      val original = ByteArray(131073) { (it % 251).toByte() }
      source.writeBytes(original)
      PdfiumWorkerVerifiedSnapshot.open(source, root, original.size.toLong(), sha(original)).use { snapshot ->
        assertEquals(original.size.toLong(), snapshot.bytes)
        assertEquals(sha(original), snapshot.sha256)
        assertFalse(root.listFiles()!!.any { it.name.startsWith("pdfium-worker-verified-") })
        source.delete()
        source.writeBytes(ByteArray(original.size) { 42 })
        val readback = ByteArray(original.size)
        snapshot.file.seek(0)
        snapshot.file.readFully(readback)
        assertArrayEquals(original, readback)
      }
    } finally { root.deleteRecursively() }
  }

  @Test fun mismatchedShaOrSizeNeverReturnsDescriptorAndCleansTemp() {
    val root = createTempDirectory("worker-snapshot-negative-").toFile()
    try {
      val source = File(root, "official.pdf")
      source.writeBytes(ByteArray(4096) { 7 })
      for (badBytes in listOf(4095L, 4097L)) {
        try {
          PdfiumWorkerVerifiedSnapshot.open(source, root, badBytes, sha(source.readBytes()))
          fail("size mismatch accepted")
        } catch (e: IllegalStateException) {
          assertEquals("PDFIUM_WORKER_SOURCE_BYTES_MISMATCH", e.message)
        }
      }
      try {
        PdfiumWorkerVerifiedSnapshot.open(source, root, 4096L, "0".repeat(64))
        fail("SHA mismatch accepted")
      } catch (e: IllegalStateException) {
        assertEquals("PDFIUM_WORKER_SOURCE_SHA256_MISMATCH", e.message)
      }
      assertEquals(listOf("official.pdf"), root.listFiles()!!.map { it.name })
    } finally { root.deleteRecursively() }
  }

  @Test fun invalidExpectationFailsBeforeCopy() {
    val root = createTempDirectory("worker-snapshot-invalid-").toFile()
    try {
      val source = File(root, "official.pdf")
      source.writeText("sample")
      try {
        PdfiumWorkerVerifiedSnapshot.open(source, root, 0, "invalid")
        fail("invalid provenance accepted")
      } catch (e: IllegalStateException) {
        assertEquals("PDFIUM_WORKER_PROVENANCE_INPUT_INVALID", e.message)
      }
    } finally { root.deleteRecursively() }
  }
}
