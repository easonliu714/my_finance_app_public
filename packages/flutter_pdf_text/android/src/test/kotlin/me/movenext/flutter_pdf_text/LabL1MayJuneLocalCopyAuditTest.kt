package me.movenext.flutter_pdf_text

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class LabL1MayJuneLocalCopyAuditTest {
  private val uri = LabL1MayJuneLocalCopyAudit.officialSortedCloud500Uri
  private val pdf = "%PDF-1.7\nsynthetic local audit fixture\n%%EOF\n".toByteArray()

  private fun fixture(block: (File, File, File) -> Unit) {
    val root = Files.createTempDirectory("lab-may-june-audit-").toFile()
    try {
      val a = File(root, "read-one.pdf").apply { writeBytes(pdf) }
      val b = File(root, "read-two.pdf").apply { writeBytes(pdf) }
      block(root, a, b)
    } finally { root.deleteRecursively() }
  }

  private fun audit(root: File, a: File, b: File,
                    period: String = "115-05-06", tier: String = "cloud-500",
                    sourceUri: String = uri, budget: Long = 200_000_000L) =
    LabL1MayJuneLocalCopyAudit.auditLocalCopies(root, a, b, period, tier, sourceUri, budget)

  private fun rejects(expected: String, block: () -> Unit) {
    try { block(); fail("Expected $expected") }
    catch (error: IllegalStateException) { assertEquals(expected, error.message) }
  }

  @Test fun matchingDistinctCopiesProduceOnlyNonAuthoritativeCandidate() = fixture { root, a, b ->
    val evidence = audit(root, a, b)
    assertEquals("115-05-06", evidence.period)
    assertEquals("cloud-500", evidence.tier)
    assertEquals(uri, evidence.publicationUri)
    assertEquals(pdf.size.toLong(), evidence.bytes)
    assertEquals(64, evidence.sha256.length)
    assertEquals("LOCAL_COPIES_ONLY_NOT_OFFICIAL_PIN", evidence.authority)
    assertNotEquals(LabOfficialPdfPreflight.OFFICIAL_SHA256, evidence.sha256)
    // Local byte agreement MUST NOT unlock the unpinned May-June source.
    rejects("L1_PERIOD_SOURCE_UNPINNED") {
      LabL1PeriodSourceIdentity.requirePinned("115-05-06", "cloud-500", evidence.sha256)
    }
  }

  @Test fun wrongPeriodTierAndUriAllFailClosed() = fixture { root, a, b ->
    rejects("L1_LOCAL_SOURCE_IDENTITY_MISMATCH") { audit(root, a, b, period = "115-07-08") }
    rejects("L1_LOCAL_SOURCE_IDENTITY_MISMATCH") { audit(root, a, b, tier = "cloud-800") }
    rejects("L1_LOCAL_SOURCE_IDENTITY_MISMATCH") { audit(root, a, b, sourceUri = "http://invoice.etax.nat.gov.tw/pdf/20260506_20260725124620_sorted_AI_D.pdf") }
    rejects("L1_LOCAL_SOURCE_IDENTITY_MISMATCH") { audit(root, a, b, sourceUri = uri + "?copy=1") }
  }

  @Test fun samePathAndHardLinkAreNotIndependentCopies() = fixture { root, a, b ->
    rejects("L1_LOCAL_COPIES_NOT_DISTINCT") { audit(root, a, a) }
    b.delete()
    Files.createLink(b.toPath(), a.toPath())
    rejects("L1_LOCAL_COPIES_NOT_DISTINCT") { audit(root, a, b) }
  }

  @Test fun changedContentWithSameByteLengthIsRejected() = fixture { root, a, b ->
    b.writeBytes(pdf.copyOf().also { it[10] = 'X'.code.toByte() })
    rejects("L1_LOCAL_COPIES_MISMATCH") { audit(root, a, b) }
  }

  @Test fun truncatedOrWrongHeaderNeverProducesCandidate() = fixture { root, a, b ->
    b.writeBytes(pdf.copyOfRange(0, pdf.size - 1))
    rejects("L1_LOCAL_COPIES_MISMATCH") { audit(root, a, b) }
    b.writeBytes("not-a-pdf".toByteArray())
    rejects("L1_LOCAL_COPY_NOT_PDF") { audit(root, a, b) }
  }

  @Test fun outsideRootAndSymlinkEscapeFailClosed() = fixture { root, a, b ->
    val outside = Files.createTempFile("lab-outside-", ".pdf").toFile()
    try {
      outside.writeBytes(pdf)
      rejects("L1_LOCAL_COPY_OUTSIDE_APP_FILES") { audit(root, a, outside) }
      b.delete()
      Files.createSymbolicLink(b.toPath(), outside.toPath())
      rejects("L1_LOCAL_COPY_OUTSIDE_APP_FILES") { audit(root, a, b) }
    } finally { outside.delete() }
  }

  @Test fun boundedStreamBudgetFailsBeforeHashAcceptance() = fixture { root, a, b ->
    rejects("L1_LOCAL_COPY_BYTES_BUDGET") { audit(root, a, b, budget = 8L) }
    rejects("L1_LOCAL_COPY_BUDGET_INVALID") { audit(root, a, b, budget = 4L) }
    rejects("L1_LOCAL_COPY_BUDGET_INVALID") { audit(root, a, b, budget = 200_000_001L) }
  }

  @Test fun noImplicitWriteAndNoRealOfficialPdfInFixtures() = fixture { root, a, b ->
    val before = root.list()?.sorted()
    val candidate = audit(root, a, b)
    assertEquals(before, root.list()?.sorted())
    assertTrue(candidate.sha256.matches(Regex("[0-9a-f]{64}")))
  }
  @Test fun identicalHeaderOnlyCopiesCannotProduceCandidate() = fixture { root, a, b ->
    val truncated = "%PDF-1.7\nheader only\n".toByteArray()
    a.writeBytes(truncated)
    b.writeBytes(truncated)
    rejects("L1_LOCAL_COPY_PDF_TRAILER_MISSING") { audit(root, a, b) }
  }

  @Test fun eofMarkerMustBeTerminalNotFollowedByNonWhitespace() = fixture { root, a, b ->
    val badTail = "%PDF-1.7\n%%EOF\ncorrupted trailing bytes".toByteArray()
    a.writeBytes(badTail)
    b.writeBytes(badTail)
    rejects("L1_LOCAL_COPY_PDF_TRAILER_MISSING") { audit(root, a, b) }
  }

  @Test fun boundedTrailerSurvivesLargeStreamAndAllowsAsciiWhitespace() = fixture { root, a, b ->
    val large = "%PDF-1.7\n".toByteArray() +
      ByteArray(8192) { 'A'.code.toByte() } +
      "\n%%EOF\r\n \t".toByteArray()
    a.writeBytes(large)
    b.writeBytes(large)
    assertEquals(large.size.toLong(), audit(root, a, b).bytes)
    val missingTerminal = "%PDF-1.7\n%%EOF\n".toByteArray() +
      ByteArray(8192) { 'A'.code.toByte() }
    a.writeBytes(missingTerminal)
    b.writeBytes(missingTerminal)
    rejects("L1_LOCAL_COPY_PDF_TRAILER_MISSING") { audit(root, a, b) }
  }

}
