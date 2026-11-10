package me.movenext.flutter_pdf_text

import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import java.nio.file.Files

/**
 * Lab-only, read-only two-copy byte audit. The returned candidate is NOT an
 * official source pin: the two files' independent HTTPS provenance remains
 * outside this API and must be verified before any period is enabled.
 */
internal object LabL1MayJuneLocalCopyAudit {
  const val officialSortedCloud500Uri =
    "https://invoice.etax.nat.gov.tw/pdf/20260506_20260725124620_sorted_AI_D.pdf"
  private const val maxPdfBytes = 200_000_000L
  private val pdfMagic = byteArrayOf(37, 80, 68, 70, 45) // %PDF-
  private val hex = "0123456789abcdef".toCharArray()

  data class Candidate(
    val period: String,
    val tier: String,
    val publicationUri: String,
    val bytes: Long,
    val sha256: String,
    val authority: String = "LOCAL_COPIES_ONLY_NOT_OFFICIAL_PIN"
  )

  private data class Digest(val bytes: Long, val sha256: String)

  fun auditLocalCopies(
    appFilesRoot: File,
    firstCopy: File,
    secondCopy: File,
    period: String,
    tier: String,
    publicationUri: String,
    byteBudget: Long = maxPdfBytes
  ): Candidate {
    if (period != LabL1PeriodSourceIdentity.mayJunePeriod ||
        tier != LabL1PeriodSourceIdentity.cloud500Tier ||
        publicationUri != officialSortedCloud500Uri) {
      throw IllegalStateException("L1_LOCAL_SOURCE_IDENTITY_MISMATCH")
    }
    if (byteBudget !in 5L..maxPdfBytes) {
      throw IllegalStateException("L1_LOCAL_COPY_BUDGET_INVALID")
    }
    val root = appFilesRoot.canonicalFile
    val first = firstCopy.canonicalFile
    val second = secondCopy.canonicalFile
    val prefix = root.path + File.separator
    if (!first.path.startsWith(prefix) || !second.path.startsWith(prefix) ||
        !first.isFile || !second.isFile) {
      throw IllegalStateException("L1_LOCAL_COPY_OUTSIDE_APP_FILES")
    }
    if (Files.isSameFile(first.toPath(), second.toPath())) {
      throw IllegalStateException("L1_LOCAL_COPIES_NOT_DISTINCT")
    }
    val a = digest(first, byteBudget)
    val b = digest(second, byteBudget)
    if (a != b) {
      throw IllegalStateException("L1_LOCAL_COPIES_MISMATCH")
    }
    if (a.sha256 == LabOfficialPdfPreflight.OFFICIAL_SHA256) {
      throw IllegalStateException("L1_LOCAL_SOURCE_REUSES_OTHER_PERIOD_SHA")
    }
    return Candidate(period, tier, publicationUri, a.bytes, a.sha256)
  }

  private fun digest(file: File, budget: Long): Digest {
    val md = MessageDigest.getInstance("SHA-256")
    var total = 0L
    val header = ByteArray(pdfMagic.size)
    var headerCount = 0
    // Retain only the final 4 KiB, never the 120 MB PDF, to reject copies
    // that have a PDF header but no terminal %%EOF marker.
    val trailer = ByteArray(4096)
    var trailerCount = 0
    FileInputStream(file).use { input ->
      val buffer = ByteArray(64 * 1024)
      while (true) {
        val n = input.read(buffer)
        if (n < 0) break
        if (n == 0) continue
        total += n
        if (total > budget) throw IllegalStateException("L1_LOCAL_COPY_BYTES_BUDGET")
        if (headerCount < header.size) {
          val count = minOf(n, header.size - headerCount)
          System.arraycopy(buffer, 0, header, headerCount, count)
          headerCount += count
        }
        if (n >= trailer.size) {
          System.arraycopy(buffer, n - trailer.size, trailer, 0, trailer.size)
          trailerCount = trailer.size
        } else if (trailerCount + n <= trailer.size) {
          System.arraycopy(buffer, 0, trailer, trailerCount, n)
          trailerCount += n
        } else {
          val drop = trailerCount + n - trailer.size
          System.arraycopy(trailer, drop, trailer, 0, trailerCount - drop)
          System.arraycopy(buffer, 0, trailer, trailerCount - drop, n)
          trailerCount = trailer.size
        }
        md.update(buffer, 0, n)
      }
    }
    if (headerCount != pdfMagic.size || !header.contentEquals(pdfMagic)) {
      throw IllegalStateException("L1_LOCAL_COPY_NOT_PDF")
    }
    // This is a bounded structural envelope check, NOT PDF parsing or an
    // official source authority proof. Only ASCII trailing whitespace is
    // allowed after the last %%EOF marker.
    var end = trailerCount - 1
    while (end >= 0 && (trailer[end] == 32.toByte() ||
        trailer[end] == 9.toByte() || trailer[end] == 10.toByte() ||
        trailer[end] == 13.toByte())) {
      end--
    }
    val eof = byteArrayOf(37, 37, 69, 79, 70) // %%EOF
    if (end < eof.size - 1 ||
        eof.indices.any { trailer[end - eof.size + 1 + it] != eof[it] }) {
      throw IllegalStateException("L1_LOCAL_COPY_PDF_TRAILER_MISSING")
    }
    val raw = md.digest()
    val chars = CharArray(raw.size * 2)
    for (i in raw.indices) {
      val b = raw[i].toInt() and 255
      chars[i * 2] = hex[b ushr 4]
      chars[i * 2 + 1] = hex[b and 15]
    }
    return Digest(total, String(chars))
  }
}
