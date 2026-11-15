package me.movenext.flutter_pdf_text

import java.io.ByteArrayInputStream
import java.security.MessageDigest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Synthetic fixtures only; no real PDF or Android full-10 UAT is asserted. */
class LabL1MayJuneOwnerPositiveGateTest {
  private val api = LabL1MayJuneOwnerAttestedBytePair
  private val oracle = LabL1MayJuneDualPdfOracle
  private fun sha(bytes: ByteArray) = MessageDigest.getInstance("SHA-256")
    .digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }

  private fun syntheticPair(): LabL1MayJuneOwnerAttestedBytePair.VerifiedPair {
    val sorted = "synthetic sorted".toByteArray()
    val draw = "synthetic draw".toByteArray()
    return api.verifyAgainstManifest(
      ByteArrayInputStream(sorted), ByteArrayInputStream(draw),
      LabL1MayJuneOwnerAttestedBytePair.Manifest(
        "115-05-06", "cloud-500", sorted.size.toLong(), sha(sorted),
        draw.size.toLong(), sha(draw)))
  }

  private fun source(role: LabL1MayJuneDualPdfOracle.Role) =
    LabL1MayJuneDualPdfOracle.Source(
      "115-05-06", "cloud-500", role,
      if (role == LabL1MayJuneDualPdfOracle.Role.SORTED) oracle.sortedUri else oracle.drawOrderUri,
      if (role == LabL1MayJuneDualPdfOracle.Role.SORTED) 119769589L else 146461156L,
      if (role == LabL1MayJuneDualPdfOracle.Role.SORTED)
        "1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe"
      else "bd80ee884233f7f38ad9004622d2bb004204f2dca50de373788e022c7018dba6",
      LabL1PeriodSourceIdentity.parserVersion)

  private fun probe(role: LabL1MayJuneDualPdfOracle.Role, token: String) =
    LabL1MayJuneDualPdfOracle.Probe(
      source(role), token, true, 1, token, listOf(token), 77000, 1, true)

  @Test fun syntheticCustodyCannotBePromotedEvenWithSessionClaim() {
    val pair = syntheticPair()
    for (token in listOf("AD22408000", "AK86067000", "AL18463159",
        "AN05056204", "BP01517997")) {
      val result = LabL1MayJuneOwnerPositiveGate.check(
        pair, probe(LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER, token),
        probe(LabL1MayJuneDualPdfOracle.Role.SORTED, token)) { _, _ -> true }
      assertEquals("L1_OWNER_PAIR_SOURCE_MISMATCH",
        (result as LabL1MayJuneDualPdfOracle.Outcome.Hold).reason)
    }
  }

  @Test fun defaultSessionIsFailClosedAndNoGlobalNegativeIsExposed() {
    val pair = syntheticPair()
    val result = LabL1MayJuneOwnerPositiveGate.check(
      pair, probe(LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER, "AD22408000"),
      probe(LabL1MayJuneDualPdfOracle.Role.SORTED, "AD22408000"))
    assertTrue(result is LabL1MayJuneDualPdfOracle.Outcome.Hold)
  }
}
