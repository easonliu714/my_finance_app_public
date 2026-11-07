package me.movenext.flutter_pdf_text

import android.os.ParcelFileDescriptor
import java.io.IOException
import java.security.MessageDigest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.rules.TemporaryFolder
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** C24 PDFium source-custody JVM/Robolectric API35, not Android device proof. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PlatformPdfiumSourceAuthorityTest {
  @get:Rule val folder = TemporaryFolder()

  private fun sha(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
    .digest(bytes).joinToString("") {
      (it.toInt() and 0xff).toString(16).padStart(2, '0')
    }

  @Test fun pdfiumDescriptorKeepsVerifiedBytesAfterOriginalPathReplacement() {
    val source = folder.newFile("pdfium-source.pdf")
    val expected = ByteArray(128 * 1024 + 13) { (it % 251).toByte() }
    source.writeBytes(expected)
    val cache = folder.newFolder("pdfium-private-cache")
    val captured = PlatformPdfiumSourceAuthority.capture(
      source, cache, expected.size.toLong(), sha(expected)
    )
    source.delete()
    source.writeText("FORGED_PDF_AT_SAME_PATH")
    assertEquals(sha(expected), captured.sha256)
    assertEquals(expected.size.toLong(), captured.bytes)
    assertArrayEquals(expected,
      ParcelFileDescriptor.AutoCloseInputStream(captured.descriptor).use { it.readBytes() })
    assertFalse(cache.listFiles().orEmpty().any {
      it.name.startsWith(".platform-source-custody-")
    })
  }

  @Test fun pdfiumNeverReceivesDescriptorForWrongExpectedSha() {
    val source = folder.newFile("pdfium-sha-mismatch.pdf")
    source.writeText("OFFICIAL_BYTES")
    val cache = folder.newFolder("pdfium-mismatch-cache")
    val error = assertThrows(IOException::class.java) {
      PlatformPdfiumSourceAuthority.capture(
        source, cache, source.length(), "0".repeat(64)
      )
    }
    assertEquals("SOURCE_CUSTODY_SHA256_MISMATCH", error.message)
    assertFalse(cache.listFiles().orEmpty().any {
      it.name.startsWith(".platform-source-custody-")
    })
  }
}
