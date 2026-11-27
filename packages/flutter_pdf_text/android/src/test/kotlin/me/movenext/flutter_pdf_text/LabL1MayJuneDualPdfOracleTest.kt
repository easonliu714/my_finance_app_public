package me.movenext.flutter_pdf_text

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Synthetic source hashes and numbers ONLY; no official winner or absent claim. */
class LabL1MayJuneDualPdfOracleTest {
  private val api = LabL1MayJuneDualPdfOracle
  private val sorted = LabL1MayJuneDualPdfOracle.Source("115-05-06", "cloud-500", LabL1MayJuneDualPdfOracle.Role.SORTED,
    api.sortedUri, 119L, "a".repeat(64), LabL1PeriodSourceIdentity.parserVersion)
  private val draw = LabL1MayJuneDualPdfOracle.Source("115-05-06", "cloud-500", LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER,
    api.drawOrderUri, 146L, "b".repeat(64), LabL1PeriodSourceIdentity.parserVersion)
  private val token = "BA12345678"
  private val sortedPage = listOf("BA12345677", token, "BA12345679")
  private val drawPage = listOf("BA99999999", token, "BA00000001")
  private val trusted: (LabL1MayJuneDualPdfOracle.Source) -> Boolean = { it == sorted || it == draw }
  private val verified: (LabL1MayJuneDualPdfOracle.AbsenceProof) -> Boolean = { true }

  private fun probe(source: LabL1MayJuneDualPdfOracle.Source, match: Boolean,
                    candidate: String = token, valid: Boolean = true) =
    LabL1MayJuneDualPdfOracle.Probe(source, candidate, match, if (match) 7 else null,
      if (match) candidate else null,
      if (match) if (source.role == LabL1MayJuneDualPdfOracle.Role.SORTED) sortedPage else drawPage else emptyList(),
      LabL1MayJuneOwnerAttestedBytePair.expectedPageCount, 7, valid)

  private fun proof(candidate: String = token, source: LabL1MayJuneDualPdfOracle.Source = draw) =
    LabL1MayJuneDualPdfOracle.AbsenceProof(source, candidate, true, true, true, "c".repeat(64))

  private fun hold(expected: String, actual: LabL1MayJuneDualPdfOracle.Outcome) {
    assertTrue("Expected HOLD $expected but got $actual", actual is LabL1MayJuneDualPdfOracle.Outcome.Hold)
    assertEquals(expected, (actual as LabL1MayJuneDualPdfOracle.Outcome.Hold).reason)
  }

  @Test fun exactCrossPdfPositiveIsOnlyDiagnosticCandidate() {
    val result = api.positive(probe(draw, true), probe(sorted, true), trusted)
    assertTrue(result is LabL1MayJuneDualPdfOracle.Outcome.PositiveCandidate)
    val found = result as LabL1MayJuneDualPdfOracle.Outcome.PositiveCandidate
    assertEquals(token, found.candidate)
    assertEquals(7, found.drawOrderPage)
    assertEquals(7, found.sortedPage)
    assertEquals("LAB_DIAGNOSTIC_ONLY", found.authority)
  }

  @Test fun noVerifiedPdfBytesMeansHoldEvenForTwoMatchingTokens() {
    hold("L1_DUAL_SOURCE_UNPINNED", api.positive(probe(draw, true), probe(sorted, true)))
  }

  @Test fun sourceUriRolePeriodTierAndDigestCannotBeReused() {
    val bad = listOf(
      draw.copy(uri = api.sortedUri), draw.copy(sha256 = sorted.sha256),
      draw.copy(period = "115-07-08"), draw.copy(tier = "cloud-800"),
      draw.copy(parserVersion = "other"), draw.copy(sha256 = "bad"),
      draw.copy(bytes = 0L))
    for (source in bad) hold("L1_DUAL_SOURCE_IDENTITY_INVALID",
      api.positive(probe(source, true), probe(sorted, true), { true }))
  }

  @Test fun fullTenCharacterEqualityAndReturnedPageTokenAreRequired() {
    hold("L1_DUAL_POSITIVE_PROBE_INVALID", api.positive(
      probe(draw, true), probe(sorted, true).copy(candidate = "BA12345679"), trusted))
    hold("L1_DUAL_POSITIVE_PROBE_INVALID", api.positive(
      probe(draw, true), probe(sorted, true).copy(returnedToken = "BA12345677"), trusted))
    hold("L1_DUAL_POSITIVE_PROBE_INVALID", api.positive(
      probe(draw, true), probe(sorted, true).copy(matchedPage = 77001), trusted))
    hold("L1_DUAL_POSITIVE_PROBE_INVALID", api.positive(
      probe(draw, true), probe(sorted, true).copy(candidate = "12345678"), trusted))
  }

  @Test fun malformedPartialOrDuplicatePageCannotClaimPositive() {
    val malformed = listOf(emptyList(), listOf(token, token),
      listOf("BA12345679", token, "BA12345677"), listOf("BA1234567X", token))
    for (tokens in malformed) hold("L1_DUAL_POSITIVE_PROBE_INVALID",
      api.positive(probe(draw, true), probe(sorted, true).copy(pageTokens = tokens), trusted))
    hold("L1_DUAL_POSITIVE_PROBE_INVALID", api.positive(
      probe(draw, true), probe(sorted, true, valid = false), trusted))
  }

  @Test fun eitherRoleWithNonExactPageCountCannotClaimPositive() {
    for (count in listOf(0, 1, 100, 76999, 77001, 100000)) {
      hold("L1_DUAL_POSITIVE_PROBE_INVALID", api.positive(
        probe(draw, true).copy(pageCount = count), probe(sorted, true), trusted))
      hold("L1_DUAL_POSITIVE_PROBE_INVALID", api.positive(
        probe(draw, true), probe(sorted, true).copy(pageCount = count), trusted))
      hold("L1_DUAL_POSITIVE_PROBE_INVALID", api.positive(
        probe(draw, true).copy(pageCount = count),
        probe(sorted, true).copy(pageCount = count), trusted))
    }
  }

  @Test fun exactPageCountDoesNotWaiveReadOrMatchBounds() {
    val count = LabL1MayJuneOwnerAttestedBytePair.expectedPageCount
    for (read in listOf(0, count + 1)) {
      hold("L1_DUAL_POSITIVE_PROBE_INVALID", api.positive(
        probe(draw, true).copy(pagesRead = read), probe(sorted, true), trusted))
      hold("L1_DUAL_NEGATIVE_PROBE_INVALID", api.negative(
        probe(sorted, false).copy(pagesRead = read), draw, proof(), trusted, verified))
    }
    val result = api.positive(
      probe(draw, true).copy(matchedPage = count),
      probe(sorted, true).copy(matchedPage = count), trusted)
    assertTrue(result is LabL1MayJuneDualPdfOracle.Outcome.PositiveCandidate)
  }

  @Test fun wrongPageCountCannotClaimNegativeEvenWithIndependentProof() {
    for (count in listOf(0, 100, 76999, 77001, 100000)) {
      hold("L1_DUAL_NEGATIVE_PROBE_INVALID", api.negative(
        probe(sorted, false).copy(pageCount = count), draw, proof(), trusted, verified))
    }
  }

  @Test fun binaryMissWithoutIndependentAbsenceProofAlwaysHolds() {
    hold("L1_DUAL_ABSENCE_PROOF_INCOMPLETE", api.negative(
      probe(sorted, false), draw, null, trusted))
    hold("L1_DUAL_ABSENCE_NOT_INDEPENDENTLY_VERIFIED", api.negative(
      probe(sorted, false), draw, proof(), trusted))
  }

  @Test fun independentlyVerifiedCompleteDrawOrderAbsenceIsStillOnlyDiagnostic() {
    val result = api.negative(probe(sorted, false), draw, proof(), trusted, verified)
    assertTrue(result is LabL1MayJuneDualPdfOracle.Outcome.NegativeCandidate)
    val absent = result as LabL1MayJuneDualPdfOracle.Outcome.NegativeCandidate
    assertEquals("LAB_DIAGNOSTIC_ONLY", absent.authority)
    assertEquals(token, absent.candidate)
  }

  @Test fun partialWrongPeriodOrWrongCandidateAbsenceProofFailsClosed() {
    val p = proof()
    val wrong = listOf(p.copy(fullCoverage = false), p.copy(allTokensValidated = false),
      p.copy(independentlyAttestedAbsent = false), p.copy(candidate = "BA12345679"),
      p.copy(drawOrderSource = draw.copy(period = "115-07-08")),
      p.copy(proofSha256 = "not-a-digest"))
    for (case in wrong) hold("L1_DUAL_ABSENCE_PROOF_INCOMPLETE",
      api.negative(probe(sorted, false), draw, case, trusted, verified))
  }

  @Test fun sortedMatchCannotBeDeclaredNegativeAndReadFailuresHold() {
    hold("L1_DUAL_NEGATIVE_PROBE_INVALID", api.negative(
      probe(sorted, true), draw, proof(), trusted, verified))
    hold("L1_DUAL_NEGATIVE_PROBE_INVALID", api.negative(
      probe(sorted, false, valid = false), draw, proof(), trusted, verified))
    hold("L1_DUAL_NEGATIVE_PROBE_INVALID", api.negative(
      probe(sorted, false).copy(matchedPage = 3), draw, proof(), trusted, verified))
  }

  @Test fun verifierExceptionsAndSourceDriftAreFailClosed() {
    hold("L1_DUAL_SOURCE_UNPINNED", api.positive(probe(draw, true),
      probe(sorted, true), { throw IllegalStateException("network failed") }))
    hold("L1_DUAL_ABSENCE_NOT_INDEPENDENTLY_VERIFIED", api.negative(
      probe(sorted, false), draw, proof(), trusted,
      { throw IllegalStateException("unavailable") }))
    val drifted = sorted.copy(sha256 = "d".repeat(64))
    hold("L1_DUAL_SOURCE_UNPINNED", api.positive(probe(draw, true),
      probe(drifted, true), trusted))
  }
}
