package me.movenext.flutter_pdf_text

import java.io.ByteArrayInputStream
import java.io.InputStream
import java.security.MessageDigest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Synthetic HTTP bodies only: never official PDF bytes or a winning ticket. */
class LabL1MayJuneOfficialStreamProvenanceTest {
  private val api = LabL1MayJuneOfficialStreamProvenance
  private val sorted = LabL1MayJuneOfficialStreamProvenance.Role.SORTED
  private val draw = LabL1MayJuneOfficialStreamProvenance.Role.DRAW_ORDER
  private val pdf = "%PDF-1.7\nsynthetic fixture\n%%EOF\n".toByteArray()

  private fun sha(bytes: ByteArray) = MessageDigest.getInstance("SHA-256")
    .digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }

  private fun audit(
    role: LabL1MayJuneOfficialStreamProvenance.Role = sorted,
    body: ByteArray = pdf,
    uri: String = api.expectedUri(role),
    status: Int = 200,
    mime: String? = "application/pdf",
    encoding: String? = null,
    length: Long? = body.size.toLong(),
    budget: Long = 200_000_000L,
    input: InputStream = ByteArrayInputStream(body)
  ) = api.auditResponse(role, uri, status, mime, encoding, length,
    "\"synthetic-etag\"", "Wed, 11 Nov 2026 00:00:00 GMT", input, budget)

  private fun rejects(reason: String, block: () -> Unit) {
    try { block(); fail("Expected $reason") }
    catch (e: IllegalStateException) { assertEquals(reason, e.message) }
  }

  @Test fun completeStreamHasDigestBytesRoleAndUnpinnedAuthority() {
    val candidate = audit()
    assertEquals(sha(pdf), candidate.sha256)
    assertEquals(pdf.size.toLong(), candidate.bytes)
    assertEquals("115-05-06", candidate.period)
    assertEquals("cloud-500", candidate.tier)
    assertEquals(api.expectedUri(sorted), candidate.uri)
    assertEquals("STREAM_CANDIDATE_NOT_OFFICIAL_PIN", candidate.authority)
    assertEquals(pdf.size.toLong(), candidate.declaredContentLength)
    rejects("L1_PERIOD_SOURCE_UNPINNED") {
      LabL1PeriodSourceIdentity.requirePinned("115-05-06", "cloud-500", candidate.sha256)
    }
  }

  @Test fun independentDifferentRoleDifferentBodyCanOnlyFormDiagnosticPair() {
    val a = audit()
    val b = audit(role = draw, body = "%PDF-1.7\nother source\n%%EOF\n".toByteArray())
    assertNotEquals(a.sha256, b.sha256)
    api.requireDistinctPair(a, b)
    assertEquals("STREAM_CANDIDATE_NOT_OFFICIAL_PIN", b.authority)
  }

  @Test fun twoSameBodiesCannotImpersonateDistinctOfficialPdfSources() {
    rejects("L1_HTTPS_DUAL_SOURCE_NOT_DISTINCT") { api.requireDistinctPair(audit(), audit(role = draw)) }
    rejects("L1_HTTPS_DUAL_SOURCE_NOT_DISTINCT") { api.requireDistinctPair(audit(role = draw), audit()) }
  }

  @Test fun roleAndUrlCannotSwapRedirectOrAddQuery() {
    rejects("L1_HTTPS_SOURCE_ROLE_URI_MISMATCH") { audit(uri = api.expectedUri(draw)) }
    rejects("L1_HTTPS_SOURCE_ROLE_URI_MISMATCH") { audit(uri = api.expectedUri(sorted) + "?copy=1") }
    rejects("L1_HTTPS_SOURCE_ROLE_URI_MISMATCH") { audit(uri = "http://invoice.etax.nat.gov.tw/file.pdf") }
    rejects("L1_HTTPS_STATUS_NOT_200") { audit(status = 302) }
    rejects("L1_HTTPS_STATUS_NOT_200") { audit(status = 403) }
    rejects("L1_HTTPS_STATUS_NOT_200") { audit(status = 429) }
  }

  @Test fun contentTypeAndEncodingMustBeUnambiguous() {
    rejects("L1_HTTPS_CONTENT_TYPE_INVALID") { audit(mime = "text/html") }
    rejects("L1_HTTPS_CONTENT_TYPE_INVALID") { audit(mime = null) }
    rejects("L1_HTTPS_CONTENT_ENCODING_UNSUPPORTED") { audit(encoding = "gzip") }
    assertEquals(sha(pdf), audit(mime = "application/pdf; charset=binary", encoding = "identity").sha256)
  }

  @Test fun contentLengthIsOnlyCandidateAndIncompleteBodiesFailClosed() {
    rejects("L1_HTTPS_INCOMPLETE_BYTES") { audit(length = pdf.size.toLong() + 1) }
    rejects("L1_HTTPS_INCOMPLETE_BYTES") { audit(length = pdf.size.toLong() - 1) }
    assertEquals(pdf.size.toLong(), audit(length = null).bytes)
    rejects("L1_HTTPS_BYTE_BUDGET_INVALID") { audit(length = 201_000_000L) }
  }

  @Test fun boundedStreamingRejectsOverflowAndInvalidBudget() {
    rejects("L1_HTTPS_BYTE_BUDGET_EXCEEDED") { audit(length = null, budget = 10L) }
    rejects("L1_HTTPS_BYTE_BUDGET_INVALID") { audit(budget = 9L) }
    rejects("L1_HTTPS_BYTE_BUDGET_INVALID") { audit(budget = 200_000_001L) }
  }

  @Test fun pdfMagicAndTerminalEofRequiredButNotClaimedAsParsing() {
    rejects("L1_HTTPS_PDF_HEADER_INVALID") { audit(body = "notpdf\n%%EOF\n".toByteArray()) }
    rejects("L1_HTTPS_PDF_TRAILER_INVALID") { audit(body = "%PDF-1.7\nheader only\n".toByteArray()) }
    rejects("L1_HTTPS_PDF_TRAILER_INVALID") { audit(body = "%PDF-1.7\n%%EOF\ncorrupt".toByteArray()) }
    assertEquals(sha(pdf), audit().sha256)
  }

  @Test fun largeStreamUsesBoundedTrailerWithoutWholeFileMemory() {
    val body = "%PDF-1.7\n".toByteArray() + ByteArray(9000) { 'X'.code.toByte() } + "\n%%EOF\r\n ".toByteArray()
    assertEquals(sha(body), audit(body = body, length = null).sha256)
  }

  @Test fun repeatedlyEmptyStreamCannotLoopForever() {
    val zero = object : InputStream() {
      override fun read(): Int = 0
      override fun read(b: ByteArray, off: Int, len: Int): Int = 0
    }
    rejects("L1_HTTPS_STREAM_STALLED") { audit(input = zero, length = null) }
  }
}
