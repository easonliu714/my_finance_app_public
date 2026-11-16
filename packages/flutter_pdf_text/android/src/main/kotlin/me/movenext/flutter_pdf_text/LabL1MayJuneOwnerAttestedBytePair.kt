package me.movenext.flutter_pdf_text

import java.io.InputStream
import java.security.MessageDigest

/**
 * L1 diagnostic-only full-byte readback of the two SHA-pinned PDFs supplied
 * by the Owner. This proves that the bytes currently read match the Owner's
 * accepted copies; it does NOT prove independently downloaded MOF bytes,
 * retain an immutable file handle, or authorize a formal award/ledger entry.
 */
internal object LabL1MayJuneOwnerAttestedBytePair {
  private const val maxBytes = 200_000_000L
  private const val sortedLength = 119_769_589L
  private const val drawLength = 146_461_156L
  private const val sortedHash =
    "1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe"
  private const val drawHash =
    "bd80ee884233f7f38ad9004622d2bb004204f2dca50de373788e022c7018dba6"

  internal data class Manifest(
    val period: String, val tier: String,
    val sortedBytes: Long, val sortedSha256: String,
    val drawBytes: Long, val drawSha256: String
  )

  internal class VerifiedPair private constructor(
    val sortedSha256: String, val drawSha256: String,
    val sortedBytes: Long, val drawBytes: Long
  ) {
    val authority: String = "LAB_OWNER_ATTESTED_BYTES_ONLY"
    companion object {
      internal fun fromVerifiedManifest(expected: Manifest): VerifiedPair =
        VerifiedPair(expected.sortedSha256, expected.drawSha256,
          expected.sortedBytes, expected.drawBytes)
    }
  }

  /** Known Owner-attested pair only; this is not an independent MOF download. */
  internal fun pinnedRole(role: LabL1MayJuneDualPdfOracle.Role): Pair<Long, String> =
    when (role) {
      LabL1MayJuneDualPdfOracle.Role.SORTED -> Pair(sortedLength, sortedHash)
      LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER -> Pair(drawLength, drawHash)
    }

  private val ownerManifest = Manifest(
    LabL1PeriodSourceIdentity.mayJunePeriod,
    LabL1PeriodSourceIdentity.cloud500Tier,
    sortedLength, sortedHash, drawLength, drawHash
  )

  /** Always verify the actual streams; caller declarations are not trusted. */
  fun verifyOwnerPair(sorted: InputStream, drawOrder: InputStream): VerifiedPair =
    verifyAgainstManifest(sorted, drawOrder, ownerManifest)

  /** Synthetic fixtures exercise the stream contract without 266 MB in Git. */
  internal fun verifyAgainstManifest(
    sorted: InputStream, drawOrder: InputStream, expected: Manifest
  ): VerifiedPair {
    if (expected.period != LabL1PeriodSourceIdentity.mayJunePeriod ||
        expected.tier != LabL1PeriodSourceIdentity.cloud500Tier ||
        expected.sortedBytes !in 10L..maxBytes ||
        expected.drawBytes !in 10L..maxBytes ||
        !Regex("[0-9a-f]{64}").matches(expected.sortedSha256) ||
        !Regex("[0-9a-f]{64}").matches(expected.drawSha256) ||
        expected.sortedSha256 == expected.drawSha256) {
      throw IllegalStateException("L1_OWNER_PAIR_MANIFEST_INVALID")
    }
    verifyStream(sorted, expected.sortedBytes, expected.sortedSha256)
    verifyStream(drawOrder, expected.drawBytes, expected.drawSha256)
    return VerifiedPair.fromVerifiedManifest(expected)
  }

  private fun verifyStream(input: InputStream, length: Long, sha256: String) {
    input.use { source ->
      val digest = MessageDigest.getInstance("SHA-256")
      val buffer = ByteArray(64 * 1024)
      var count = 0L
      var emptyReads = 0
      while (true) {
        val n = source.read(buffer)
        if (n < 0) break
        if (n == 0) {
          if (++emptyReads > 32) throw IllegalStateException("L1_OWNER_PAIR_STREAM_STALLED")
          continue
        }
        emptyReads = 0
        if (n > length - count) {
          throw IllegalStateException("L1_OWNER_PAIR_BYTES_MISMATCH")
        }
        count += n
        digest.update(buffer, 0, n)
      }
      if (count != length) {
        throw IllegalStateException("L1_OWNER_PAIR_BYTES_MISMATCH")
      }
      val actual = digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
      if (actual != sha256) {
        throw IllegalStateException("L1_OWNER_PAIR_SHA_MISMATCH")
      }
    }
  }

  /** This only binds an already rehashed pair to a diagnostic Oracle source. */
  fun matchesDiagnosticSource(
    verified: VerifiedPair, source: LabL1MayJuneDualPdfOracle.Source
  ): Boolean {
    if (verified.sortedSha256 != sortedHash || verified.drawSha256 != drawHash ||
        verified.sortedBytes != sortedLength || verified.drawBytes != drawLength ||
        source.period != LabL1PeriodSourceIdentity.mayJunePeriod ||
        source.tier != LabL1PeriodSourceIdentity.cloud500Tier ||
        source.parserVersion != LabL1PeriodSourceIdentity.parserVersion) return false
    return when (source.role) {
      LabL1MayJuneDualPdfOracle.Role.SORTED ->
        source.uri == LabL1MayJuneDualPdfOracle.sortedUri &&
          source.bytes == sortedLength && source.sha256 == sortedHash
      LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER ->
        source.uri == LabL1MayJuneDualPdfOracle.drawOrderUri &&
          source.bytes == drawLength && source.sha256 == drawHash
    }
  }
}
