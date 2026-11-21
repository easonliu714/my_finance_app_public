package me.movenext.flutter_pdf_text

import org.junit.Assert.assertTrue
import org.junit.Test

class LabL1NativeDualProbeBridgeTest {
  private val candidate = "AB12345678"
  private val draw = "native-draw"
  private val sorted = "native-sorted"
  private val dr = LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER
  private val sr = LabL1MayJuneDualPdfOracle.Role.SORTED
  private val roles = mapOf(draw to dr, sorted to sr)
  private val receipts = roles.mapValues { (_, role) ->
    val pin = LabL1MayJuneOwnerAttestedBytePair.pinnedRole(role)
    LabL1VerifiedPdfSnapshot.Expected(role, pin.first, pin.second)
  }
  private fun page(id: String, role: LabL1MayJuneDualPdfOracle.Role): Map<String, Any> {
    val pin = LabL1MayJuneOwnerAttestedBytePair.pinnedRole(role)
    return mapOf(
      "sessionId" to id,
      "role" to if (role == sr) "sorted" else "draw_order",
      "sourceBytes" to pin.first, "sourceSha256" to pin.second,
      "period" to LabL1PeriodSourceIdentity.mayJunePeriod,
      "tier" to LabL1PeriodSourceIdentity.cloud500Tier,
      "parserVersion" to LabL1PeriodSourceIdentity.parserVersion,
      "pageNumber" to 1, "pageCount" to 77_000,
      "extractionComplete" to true, "tokens" to listOf(candidate),
      "authority" to "LAB_PDFIUM_PAGE_TOKENS_ONLY"
    )
  }
  private val pages get() = mapOf(draw to page(draw, dr), sorted to page(sorted, sr))
  private fun check(
    d: String = draw, s: String = sorted,
    p: Map<String, Map<String, Any>> = pages,
    r: Map<String, LabL1MayJuneDualPdfOracle.Role> = roles,
    receiptsArg: Map<String, LabL1VerifiedPdfSnapshot.Expected> = receipts,
    live: Set<String> = roles.keys,
    token: String = candidate
  ) = LabL1NativeDualProbeBridge.positive(token, d, s, p, r, receiptsArg, live)
  private fun held(value: LabL1MayJuneDualPdfOracle.Outcome) =
    assertTrue(value is LabL1MayJuneDualPdfOracle.Outcome.Hold)

  @Test fun independentRoleBoundNativePagesReachDiagnosticOracle() {
    assertTrue(check() is LabL1MayJuneDualPdfOracle.Outcome.PositiveCandidate)
  }
  @Test fun truncatedOrInflatedOfficialPageCountCannotYieldDiagnosticPositive() {
    held(check(p = pages + (sorted to (pages.getValue(sorted) + ("pageCount" to 2)))))
    held(check(p = pages + (draw to (pages.getValue(draw) + ("pageCount" to 76_999)))))
    held(check(p = pages + (sorted to (pages.getValue(sorted) + ("pageCount" to 77_001)))))
    assertTrue(check() is LabL1MayJuneDualPdfOracle.Outcome.PositiveCandidate)
  }
  @Test fun swappedRoleAndSameSessionReplayHold() {
    held(check(d = sorted, s = draw))
    held(check(s = draw))
  }
  @Test fun missingOrClosedSecondSessionHold() {
    held(check(p = pages - sorted))
    held(check(live = setOf(draw)))
  }
  @Test fun wrongReceiptAndWrongPeriodHold() {
    held(check(receiptsArg = receipts + (sorted to receipts.getValue(draw))))
    held(check(p = pages + (sorted to (pages.getValue(sorted) + ("period" to "115-07-08")))))
  }
  @Test fun partialOrMalformedCandidateAndMissingPageHold() {
    held(check(token = "AB1234567"))
    held(check(p = pages + (draw to (pages.getValue(draw) + ("tokens" to listOf("AB1234567"))))))
    held(check(p = pages + (draw to (pages.getValue(draw) + ("pageNumber" to 0)))))
  }
}
