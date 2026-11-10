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
        md.update(buffer, 0, n)
      }
    }
    if (headerCount != pdfMagic.size || !header.contentEquals(pdfMagic)) {
      throw IllegalStateException("L1_LOCAL_COPY_NOT_PDF")
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
