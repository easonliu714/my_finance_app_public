package me.movenext.flutter_pdf_text

/**
 * Lab-only, pure contract for independent May-June Cloud-500 PDF cross-checks.
 * No network, file, cursor, ledger or Android integration. In particular, a
 * diagnostic concordance is never a formal WIN / NOT_WIN determination.
 *
 * The injected verifiers must independently authenticate the exact PDF bytes
 * and, for absence, a complete draw-order source. Defaults fail closed.
 */
internal object LabL1MayJuneDualPdfOracle {
  enum class Role { SORTED, DRAW_ORDER }

  const val sortedUri =
    "https://invoice.etax.nat.gov.tw/pdf/20260506_20260725124620_sorted_AI_D.pdf"
  const val drawOrderUri =
    "https://invoice.etax.nat.gov.tw/pdf/20260506_20260725124620_AI_D.pdf"
  private const val maxPdfBytes = 200_000_000L
  private val invoice = Regex("[A-Z]{2}[0-9]{8}")
  private val sha256 = Regex("[0-9a-f]{64}")

  data class Source(
    val period: String,
    val tier: String,
    val role: Role,
    val uri: String,
    val bytes: Long,
    val sha256: String,
    val parserVersion: String
  )

  data class Probe(
    val source: Source,
    val candidate: String,
    val matched: Boolean,
    val matchedPage: Int?,
    val returnedToken: String?,
    val pageTokens: List<String>,
    val pageCount: Int,
    val pagesRead: Int,
    val extractionComplete: Boolean
  )

  /** Absence needs independently verified COMPLETE coverage of draw-order PDF. */
  data class AbsenceProof(
    val drawOrderSource: Source,
    val candidate: String,
    val fullCoverage: Boolean,
    val allTokensValidated: Boolean,
    val independentlyAttestedAbsent: Boolean,
    val proofSha256: String
  )

  sealed class Outcome {
    data class PositiveCandidate(
      val candidate: String,
      val drawOrderPage: Int,
      val sortedPage: Int,
      val authority: String = "LAB_DIAGNOSTIC_ONLY"
    ) : Outcome()
    data class NegativeCandidate(
      val candidate: String,
      val independentProofSha256: String,
      val authority: String = "LAB_DIAGNOSTIC_ONLY"
    ) : Outcome()
    data class Hold(val reason: String) : Outcome()
  }

  private fun sourcesValid(sorted: Source, draw: Source): Boolean {
    if (sorted.role != Role.SORTED || draw.role != Role.DRAW_ORDER ||
        sorted.uri != sortedUri || draw.uri != drawOrderUri ||
        sorted.uri == draw.uri || sorted.sha256 == draw.sha256) return false
    return listOf(sorted, draw).all { source ->
      source.period == LabL1PeriodSourceIdentity.mayJunePeriod &&
        source.tier == LabL1PeriodSourceIdentity.cloud500Tier &&
        source.bytes in 1L..maxPdfBytes &&
        sha256.matches(source.sha256) &&
        source.parserVersion == LabL1PeriodSourceIdentity.parserVersion
    }
  }

  private fun probeValid(probe: Probe, expected: Source, requireMatch: Boolean): Boolean {
    if (probe.source != expected || !invoice.matches(probe.candidate) ||
        probe.pageCount !in 1..100_000 || probe.pagesRead !in 1..probe.pageCount ||
        !probe.extractionComplete || probe.matched != requireMatch) return false
    if (!requireMatch) {
      // A sampled binary miss alone is NOT an independent absence oracle.
      return probe.matchedPage == null && probe.returnedToken == null &&
        probe.pageTokens.isEmpty()
    }
    val tokens = probe.pageTokens
    return probe.matchedPage != null && probe.matchedPage in 1..probe.pageCount &&
      probe.returnedToken == probe.candidate &&
      tokens.size in 1..50 && tokens.all { invoice.matches(it) } &&
      tokens.toSet().size == tokens.size && tokens.contains(probe.candidate) &&
      (expected.role != Role.SORTED || tokens.zipWithNext().all { (a, b) -> a < b })
  }

  private fun verifiedSources(
    sorted: Source,
    draw: Source,
    verifyPinnedSource: (Source) -> Boolean
  ): Boolean = try {
    verifyPinnedSource(sorted) && verifyPinnedSource(draw)
  } catch (_: Exception) { false }

  fun positive(
    draw: Probe,
    sorted: Probe,
    verifyPinnedSource: (Source) -> Boolean = { false }
  ): Outcome {
    if (!sourcesValid(sorted.source, draw.source))
      return Outcome.Hold("L1_DUAL_SOURCE_IDENTITY_INVALID")
    if (!verifiedSources(sorted.source, draw.source, verifyPinnedSource))
      return Outcome.Hold("L1_DUAL_SOURCE_UNPINNED")
    if (draw.candidate != sorted.candidate ||
        !probeValid(draw, draw.source, true) ||
        !probeValid(sorted, sorted.source, true))
      return Outcome.Hold("L1_DUAL_POSITIVE_PROBE_INVALID")
    return Outcome.PositiveCandidate(
      sorted.candidate, draw.matchedPage!!, sorted.matchedPage!!)
  }

  fun negative(
    sorted: Probe,
    drawOrderSource: Source,
    proof: AbsenceProof?,
    verifyPinnedSource: (Source) -> Boolean = { false },
    verifyIndependentAbsence: (AbsenceProof) -> Boolean = { false }
  ): Outcome {
    if (!sourcesValid(sorted.source, drawOrderSource))
      return Outcome.Hold("L1_DUAL_SOURCE_IDENTITY_INVALID")
    if (!verifiedSources(sorted.source, drawOrderSource, verifyPinnedSource))
      return Outcome.Hold("L1_DUAL_SOURCE_UNPINNED")
    if (!probeValid(sorted, sorted.source, false))
      return Outcome.Hold("L1_DUAL_NEGATIVE_PROBE_INVALID")
    if (proof == null || proof.drawOrderSource != drawOrderSource ||
        proof.candidate != sorted.candidate || !proof.fullCoverage ||
        !proof.allTokensValidated || !proof.independentlyAttestedAbsent ||
        !sha256.matches(proof.proofSha256))
      return Outcome.Hold("L1_DUAL_ABSENCE_PROOF_INCOMPLETE")
    val independent = try { verifyIndependentAbsence(proof) } catch (_: Exception) { false }
    if (!independent) return Outcome.Hold("L1_DUAL_ABSENCE_NOT_INDEPENDENTLY_VERIFIED")
    return Outcome.NegativeCandidate(sorted.candidate, proof.proofSha256)
  }
}
