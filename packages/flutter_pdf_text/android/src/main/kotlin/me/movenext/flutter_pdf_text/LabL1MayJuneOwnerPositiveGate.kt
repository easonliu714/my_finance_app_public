package me.movenext.flutter_pdf_text

/**
 * Lab-only bridge from Owner-attested byte custody to the existing full-10
 * dual-PDF positive contract. A hash readback is NOT an immutable parser handle:
 * callers must independently prove the two probes came from the same verified
 * point-of-use session. The default session verifier always rejects.
 */
internal object LabL1MayJuneOwnerPositiveGate {
  fun check(
    pair: LabL1MayJuneOwnerAttestedBytePair.VerifiedPair,
    draw: LabL1MayJuneDualPdfOracle.Probe,
    sorted: LabL1MayJuneDualPdfOracle.Probe,
    verifySameSession: (
      LabL1MayJuneDualPdfOracle.Probe,
      LabL1MayJuneDualPdfOracle.Probe
    ) -> Boolean = { _, _ -> false }
  ): LabL1MayJuneDualPdfOracle.Outcome {
    if (!LabL1MayJuneOwnerAttestedBytePair.matchesDiagnosticSource(pair, draw.source) ||
        !LabL1MayJuneOwnerAttestedBytePair.matchesDiagnosticSource(pair, sorted.source)) {
      return LabL1MayJuneDualPdfOracle.Outcome.Hold("L1_OWNER_PAIR_SOURCE_MISMATCH")
    }
    val sameSession = try { verifySameSession(draw, sorted) }
      catch (_: Exception) { false }
    if (!sameSession) {
      return LabL1MayJuneDualPdfOracle.Outcome.Hold("L1_OWNER_PAIR_SESSION_UNVERIFIED")
    }
    return LabL1MayJuneDualPdfOracle.positive(draw, sorted) { source ->
      LabL1MayJuneOwnerAttestedBytePair.matchesDiagnosticSource(pair, source)
    }
  }
}
