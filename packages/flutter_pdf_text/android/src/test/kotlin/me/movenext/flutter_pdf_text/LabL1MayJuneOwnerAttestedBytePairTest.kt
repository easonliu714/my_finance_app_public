package me.movenext.flutter_pdf_text

import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream
import java.security.MessageDigest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Fixtures are synthetic; full Owner PDF hashes are never generated in CI. */
class LabL1MayJuneOwnerAttestedBytePairTest {
  private val api = LabL1MayJuneOwnerAttestedBytePair
  private val sorted = "%PDF-1.5\nsorted synthetic source\n%%EOF\n".toByteArray()
  private val draw = "%PDF-1.5\ndraw-order synthetic source\n%%EOF\n".toByteArray()
  private fun sha(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
    .digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }

  private fun manifest() = LabL1MayJuneOwnerAttestedBytePair.Manifest(
    "115-05-06", "cloud-500", sorted.size.toLong(), sha(sorted),
    draw.size.toLong(), sha(draw))

  private fun check(
    sortedBytes: ByteArray = sorted, drawBytes: ByteArray = draw,
    expected: LabL1MayJuneOwnerAttestedBytePair.Manifest = manifest()
  ) = api.verifyAgainstManifest(
    ByteArrayInputStream(sortedBytes), ByteArrayInputStream(drawBytes), expected)

  private fun rejects(expected: String, block: () -> Unit) {
    try { block(); fail("Expected $expected") }
    catch (error: IllegalStateException) { assertEquals(expected, error.message) }
  }

  @Test fun exactDistinctByteStreamsProduceDiagnosticOnlyCustody() {
    val checked = check()
    assertEquals(sha(sorted), checked.sortedSha256)
    assertEquals(sha(draw), checked.drawSha256)
    assertEquals(sorted.size.toLong(), checked.sortedBytes)
    assertEquals(draw.size.toLong(), checked.drawBytes)
    assertEquals("LAB_OWNER_ATTESTED_BYTES_ONLY", checked.authority)
    rejects("L1_PERIOD_SOURCE_UNPINNED") {
      LabL1PeriodSourceIdentity.requirePinned("115-05-06", "cloud-500", checked.sortedSha256)
    }
  }

  @Test fun swappedFilesAndTruncationFailClosed() {
    rejects("L1_OWNER_PAIR_BYTES_MISMATCH") { check(draw, sorted) }
    rejects("L1_OWNER_PAIR_BYTES_MISMATCH") { check(sorted.copyOf(sorted.size - 1)) }
    rejects("L1_OWNER_PAIR_BYTES_MISMATCH") { check(drawBytes = draw + byteArrayOf(0)) }
  }

  @Test fun sameLengthTamperCannotPassDigest() {
    val tampered = sorted.copyOf()
    tampered[10] = (tampered[10].toInt() xor 1).toByte()
    rejects("L1_OWNER_PAIR_SHA_MISMATCH") { check(sortedBytes = tampered) }
    val changedDraw = draw.copyOf()
    changedDraw[10] = (changedDraw[10].toInt() xor 1).toByte()
    rejects("L1_OWNER_PAIR_SHA_MISMATCH") { check(drawBytes = changedDraw) }
  }

  @Test fun badManifestNeverStartsReading() {
    val m = manifest()
    val invalid = listOf(
      m.copy(period = "115-07-08"), m.copy(tier = "cloud-800"),
      m.copy(sortedBytes = 0), m.copy(drawBytes = 200_000_001L),
      m.copy(sortedSha256 = "bad"), m.copy(drawSha256 = m.sortedSha256))
    for (candidate in invalid) rejects("L1_OWNER_PAIR_MANIFEST_INVALID") {
      check(expected = candidate)
    }
  }

  @Test fun zeroLengthReadsCannotLoopIndefinitely() {
    val zero = object : InputStream() {
      override fun read(): Int = 0
      override fun read(b: ByteArray, off: Int, len: Int): Int = 0
    }
    rejects("L1_OWNER_PAIR_STREAM_STALLED") {
      api.verifyAgainstManifest(zero, ByteArrayInputStream(draw), manifest())
    }
  }

  @Test fun ownerRealManifestCannotAcceptSyntheticBytes() {
    rejects("L1_OWNER_PAIR_BYTES_MISMATCH") {
      api.verifyOwnerPair(ByteArrayInputStream(sorted), ByteArrayInputStream(draw))
    }
  }

  @Test fun readFailureCannotProduceVerifiedPair() {
    val broken = object : InputStream() {
      override fun read(): Int = throw IOException("simulated read error")
      override fun read(b: ByteArray, off: Int, len: Int): Int =
        throw IOException("simulated read error")
    }
    try {
      api.verifyAgainstManifest(broken, ByteArrayInputStream(draw), manifest())
      fail("broken stream must be rejected")
    } catch (_: IOException) { /* no candidate is returned */ }
  }

  @Test fun syntheticVerifiedPairCannotAuthorizeActualOfficialSource() {
    val verified = check()
    val source = LabL1MayJuneDualPdfOracle.Source(
      "115-05-06", "cloud-500", LabL1MayJuneDualPdfOracle.Role.SORTED,
      LabL1MayJuneDualPdfOracle.sortedUri, 119769589L,
      "1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe",
      LabL1PeriodSourceIdentity.parserVersion)
    assertFalse(api.matchesDiagnosticSource(verified, source))
    assertFalse(api.matchesDiagnosticSource(verified, source.copy(period = "115-07-08")))
    assertTrue(verified.authority != "OFFICIAL_AWARD_POSTING")
  }
}
