package me.movenext.flutter_pdf_text

import java.io.File
import java.security.MessageDigest

/** Lab-only bounded source custody. This is not page-extraction authority. */
internal object LabOfficialPdfPreflight {
  const val OFFICIAL_BYTES = 135200798L
  const val OFFICIAL_SHA256 = "f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571"

  fun verify(
    source: File,
    appFilesRoot: File,
    expectedBytes: Long = OFFICIAL_BYTES,
    expectedSha256: String = OFFICIAL_SHA256
  ): String {
    val root = appFilesRoot.canonicalFile
    val file = source.canonicalFile
    if (!file.path.startsWith(root.path + File.separator)) {
      throw IllegalStateException("L1_SOURCE_OUTSIDE_APP_FILES")
    }
    if (!file.isFile || file.length() != expectedBytes) {
      throw IllegalStateException("L1_OFFICIAL_BYTES_MISMATCH")
    }
    val modifiedBefore = file.lastModified()
    val digest = MessageDigest.getInstance("SHA-256")
    var total = 0L
    file.inputStream().buffered(1024 * 1024).use { input ->
      val buffer = ByteArray(1024 * 1024)
      while (true) {
        val count = input.read(buffer)
        if (count < 0) break
        digest.update(buffer, 0, count)
        total += count
        if (total > expectedBytes) {
          throw IllegalStateException("L1_OFFICIAL_BYTES_MISMATCH")
        }
      }
    }
    if (total != expectedBytes || file.length() != expectedBytes ||
        file.lastModified() != modifiedBefore) {
      throw IllegalStateException("L1_SOURCE_CHANGED_DURING_PREFLIGHT")
    }
    val actualSha256 = digest.digest().joinToString("") {
      "%02x".format(it.toInt() and 0xff)
    }
    if (actualSha256 != expectedSha256) {
      throw IllegalStateException("L1_OFFICIAL_SHA_MISMATCH")
    }
    return actualSha256
  }
}
