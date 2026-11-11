package me.movenext.flutter_pdf_text

import java.io.InputStream
import java.net.URL
import java.security.MessageDigest
import javax.net.ssl.HttpsURLConnection

/**
 * Lab-only bounded HTTPS source acquisition. A complete streamed digest is a
 * source CANDIDATE, never an independent official byte pin or a prize oracle.
 * No private tickets, ledger, cursor, JSONL or July-August source are touched.
 */
internal object LabL1MayJuneOfficialStreamProvenance {
  enum class Role { SORTED, DRAW_ORDER }

  private const val maxPdfBytes = 200_000_000L
  // A socket read timeout is not a whole-download deadline: slow trickles
  // could otherwise hold the Lab worker indefinitely within the byte cap.
  private const val maxStreamDurationNanos = 30L * 60L * 1_000_000_000L
  private val pdfMagic = "%PDF-".toByteArray(Charsets.US_ASCII)
  private val pdfEof = "%%EOF".toByteArray(Charsets.US_ASCII)

  data class Candidate(
    val period: String,
    val tier: String,
    val role: Role,
    val uri: String,
    val bytes: Long,
    val sha256: String,
    val parserVersion: String,
    val declaredContentLength: Long?,
    val etag: String?,
    val lastModified: String?,
    val authority: String = "STREAM_CANDIDATE_NOT_OFFICIAL_PIN"
  )

  fun expectedUri(role: Role): String = when (role) {
    Role.SORTED -> LabL1MayJuneDualPdfOracle.sortedUri
    Role.DRAW_ORDER -> LabL1MayJuneDualPdfOracle.drawOrderUri
  }

  /**
   * Production transport uses the platform TLS trust store, an exact official
   * HTTPS URL, no redirects, no compression, and finite socket timeouts.
   * Never treat a HEAD response or Content-Length as a downloaded source.
   */
  fun fetchOfficial(role: Role, byteBudget: Long = maxPdfBytes): Candidate {
    if (byteBudget !in 10L..maxPdfBytes) {
      throw IllegalStateException("L1_HTTPS_BYTE_BUDGET_INVALID")
    }
    val uri = expectedUri(role)
    val connection = URL(uri).openConnection() as HttpsURLConnection
    connection.instanceFollowRedirects = false
    connection.useCaches = false
    connection.connectTimeout = 10_000
    connection.readTimeout = 30_000
    connection.setRequestProperty("Accept", "application/pdf")
    connection.setRequestProperty("Accept-Encoding", "identity")
    try {
      if (connection.responseCode != HttpsURLConnection.HTTP_OK) {
        throw IllegalStateException("L1_HTTPS_STATUS_NOT_200")
      }
      val contentLength = connection.getHeaderFieldLong("Content-Length", -1L)
        .takeIf { it >= 0L }
      return connection.inputStream.use { stream ->
        auditResponse(
          role = role,
          requestUri = connection.url.toExternalForm(),
          httpStatus = connection.responseCode,
          contentType = connection.contentType,
          contentEncoding = connection.contentEncoding,
          declaredContentLength = contentLength,
          etag = connection.getHeaderField("ETag"),
          lastModified = connection.getHeaderField("Last-Modified"),
          stream = stream,
          byteBudget = byteBudget
        ).copy(authority = "HTTPS_STREAM_CANDIDATE_NOT_OFFICIAL_PIN")
      }
    } finally {
      connection.disconnect()
    }
  }

  /** Testable streaming core; caller-supplied metadata is NOT HTTPS authority. */
  fun auditResponse(
    role: Role,
    requestUri: String,
    httpStatus: Int,
    contentType: String?,
    contentEncoding: String?,
    declaredContentLength: Long?,
    etag: String?,
    lastModified: String?,
    stream: InputStream,
    byteBudget: Long = maxPdfBytes,
    monotonicNanos: () -> Long = System::nanoTime
  ): Candidate {
    if (requestUri != expectedUri(role)) {
      throw IllegalStateException("L1_HTTPS_SOURCE_ROLE_URI_MISMATCH")
    }
    if (httpStatus != 200) throw IllegalStateException("L1_HTTPS_STATUS_NOT_200")
    if (contentType?.substringBefore(';')?.trim()?.lowercase() != "application/pdf") {
      throw IllegalStateException("L1_HTTPS_CONTENT_TYPE_INVALID")
    }
    if (contentEncoding != null && !contentEncoding.equals("identity", ignoreCase = true)) {
      throw IllegalStateException("L1_HTTPS_CONTENT_ENCODING_UNSUPPORTED")
    }
    if (byteBudget !in 10L..maxPdfBytes ||
        (declaredContentLength != null && declaredContentLength !in 10L..byteBudget)) {
      throw IllegalStateException("L1_HTTPS_BYTE_BUDGET_INVALID")
    }

    val digest = MessageDigest.getInstance("SHA-256")
    val header = ByteArray(pdfMagic.size)
    var headerCount = 0
    val trailer = ByteArray(4096)
    var trailerCount = 0
    var total = 0L
    var emptyReads = 0
    val buffer = ByteArray(64 * 1024)
    val startedNanos = monotonicNanos()
    fun requireWithinDeadline() {
      if (monotonicNanos() - startedNanos >= maxStreamDurationNanos) {
        throw IllegalStateException("L1_HTTPS_STREAM_DEADLINE_EXCEEDED")
      }
    }
    while (true) {
      requireWithinDeadline()
      val n = stream.read(buffer)
      requireWithinDeadline()
      if (n < 0) break
      if (n == 0) {
        if (++emptyReads > 32) throw IllegalStateException("L1_HTTPS_STREAM_STALLED")
        continue
      }
      emptyReads = 0
      if (n > byteBudget - total) throw IllegalStateException("L1_HTTPS_BYTE_BUDGET_EXCEEDED")
      total += n
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
      digest.update(buffer, 0, n)
    }
    if (total < 10L || (declaredContentLength != null && total != declaredContentLength)) {
      throw IllegalStateException("L1_HTTPS_INCOMPLETE_BYTES")
    }
    if (headerCount != pdfMagic.size || !header.contentEquals(pdfMagic)) {
      throw IllegalStateException("L1_HTTPS_PDF_HEADER_INVALID")
    }
    var end = trailerCount - 1
    while (end >= 0 && trailer[end] in arrayOf(9.toByte(), 10.toByte(), 13.toByte(), 32.toByte())) {
      end--
    }
    if (end < pdfEof.size - 1 ||
        pdfEof.indices.any { trailer[end - pdfEof.size + 1 + it] != pdfEof[it] }) {
      throw IllegalStateException("L1_HTTPS_PDF_TRAILER_INVALID")
    }
    val sha = digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
    if (sha == LabOfficialPdfPreflight.OFFICIAL_SHA256) {
      throw IllegalStateException("L1_HTTPS_OTHER_PERIOD_SHA_REUSED")
    }
    return Candidate(
      LabL1PeriodSourceIdentity.mayJunePeriod,
      LabL1PeriodSourceIdentity.cloud500Tier,
      role, requestUri, total, sha, LabL1PeriodSourceIdentity.parserVersion,
      declaredContentLength, etag, lastModified
    )
  }

  /** Different official URLs and distinct complete digests, not two copies. */
  fun requireDistinctPair(sorted: Candidate, drawOrder: Candidate) {
    if (sorted.role != Role.SORTED || drawOrder.role != Role.DRAW_ORDER ||
        sorted.uri != expectedUri(Role.SORTED) ||
        drawOrder.uri != expectedUri(Role.DRAW_ORDER) ||
        sorted.period != LabL1PeriodSourceIdentity.mayJunePeriod ||
        drawOrder.period != LabL1PeriodSourceIdentity.mayJunePeriod ||
        sorted.tier != LabL1PeriodSourceIdentity.cloud500Tier ||
        drawOrder.tier != LabL1PeriodSourceIdentity.cloud500Tier ||
        sorted.parserVersion != LabL1PeriodSourceIdentity.parserVersion ||
        drawOrder.parserVersion != LabL1PeriodSourceIdentity.parserVersion ||
        sorted.bytes < 10L || drawOrder.bytes < 10L ||
        sorted.sha256 == drawOrder.sha256) {
      throw IllegalStateException("L1_HTTPS_DUAL_SOURCE_NOT_DISTINCT")
    }
  }
}
