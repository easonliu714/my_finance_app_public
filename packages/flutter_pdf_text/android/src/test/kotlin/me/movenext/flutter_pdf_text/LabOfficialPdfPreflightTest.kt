package me.movenext.flutter_pdf_text

import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.nio.file.Files
import java.security.MessageDigest

class LabOfficialPdfPreflightTest {
  @get:Rule val folder = TemporaryFolder()

  private fun digest(bytes: ByteArray): String =
    MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") {
      "%02x".format(it.toInt() and 0xff)
    }

  private fun expectFailure(code: String, block: () -> Unit) {
    try {
      block()
      fail("expected $code")
    } catch (error: IllegalStateException) {
      assertEquals(code, error.message)
    }
  }

  @Test fun exactBytesAndHashPass() {
    val data = "lab-native-source".toByteArray()
    val file = folder.newFile("source.pdf").apply { writeBytes(data) }
    assertEquals(digest(data), LabOfficialPdfPreflight.verify(
      file, folder.root, data.size.toLong(), digest(data)))
  }

  @Test fun wrongSizeFailsBeforeHash() {
    val data = "lab-native-source".toByteArray()
    val file = folder.newFile("source.pdf").apply { writeBytes(data) }
    expectFailure("L1_OFFICIAL_BYTES_MISMATCH") {
      LabOfficialPdfPreflight.verify(
        file, folder.root, data.size.toLong() + 1, digest(data))
    }
  }

  @Test fun sameLengthWrongHashFails() {
    val data = "lab-native-source".toByteArray()
    val file = folder.newFile("source.pdf").apply { writeBytes(data) }
    expectFailure("L1_OFFICIAL_SHA_MISMATCH") {
      LabOfficialPdfPreflight.verify(
        file, folder.root, data.size.toLong(), "0".repeat(64))
    }
  }

  @Test fun externalPathFailsClosed() {
    val data = "lab-native-source".toByteArray()
    val outside = Files.createTempFile("l1-outside", ".pdf").toFile()
    try {
      outside.writeBytes(data)
      expectFailure("L1_SOURCE_OUTSIDE_APP_FILES") {
        LabOfficialPdfPreflight.verify(
          outside, folder.root, data.size.toLong(), digest(data))
      }
    } finally {
      outside.delete()
    }
  }

  @Test fun symlinkEscapeFailsClosed() {
    val data = "lab-native-source".toByteArray()
    val outside = Files.createTempFile("l1-outside", ".pdf").toFile()
    try {
      outside.writeBytes(data)
      val link = File(folder.root, "linked.pdf")
      Files.createSymbolicLink(link.toPath(), outside.toPath())
      expectFailure("L1_SOURCE_OUTSIDE_APP_FILES") {
        LabOfficialPdfPreflight.verify(
          link, folder.root, data.size.toLong(), digest(data))
      }
    } finally {
      outside.delete()
    }
  }

  @Test fun modifiedSameLengthSourceFailsHash() {
    val original = "source-AAAA".toByteArray()
    val modified = "source-BBBB".toByteArray()
    val file = folder.newFile("source.pdf").apply { writeBytes(modified) }
    expectFailure("L1_OFFICIAL_SHA_MISMATCH") {
      LabOfficialPdfPreflight.verify(
        file, folder.root, original.size.toLong(), digest(original))
    }
  }
}
