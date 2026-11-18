package me.movenext.flutter_pdf_text

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class LabL1PdfiumTokenResponseTest {
  private fun receipt(role: LabL1MayJuneDualPdfOracle.Role): LabL1VerifiedPdfSnapshot.Expected {
    val pin = LabL1MayJuneOwnerAttestedBytePair.pinnedRole(role)
    return LabL1VerifiedPdfSnapshot.Expected(role, pin.first, pin.second)
  }
  @Test fun nativePageProducesBoundedRoleTaggedTokens() {
    val actual = LabL1PdfiumTokenResponse.fromVerifiedPage(
      "verified-session", LabL1MayJuneDualPdfOracle.Role.SORTED,
      2, 3, "AB12345678 CD87654321", receipt(LabL1MayJuneDualPdfOracle.Role.SORTED)
    )
    assertEquals("sorted", actual["role"])
    assertEquals(2, actual["pageNumber"])
    assertEquals(3, actual["pageCount"])
    assertEquals(listOf("AB12345678", "CD87654321"), actual["tokens"])
    assertEquals(true, actual["extractionComplete"])
    assertEquals("LAB_PDFIUM_PAGE_TOKENS_ONLY", actual["authority"])
  }

  @Test fun roleBoundPdfiumPageCarriesExactOwnerAttestedPinNotCallerMetadata() {
    val sorted = LabL1PdfiumTokenResponse.fromVerifiedPage(
      "sorted-session", LabL1MayJuneDualPdfOracle.Role.SORTED, 1, 2, "AB12345678", receipt(LabL1MayJuneDualPdfOracle.Role.SORTED))
    val draw = LabL1PdfiumTokenResponse.fromVerifiedPage(
      "draw-session", LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER, 1, 2, "AB12345678", receipt(LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER))
    for (role in LabL1MayJuneDualPdfOracle.Role.values()) {
      val actual = if (role == LabL1MayJuneDualPdfOracle.Role.SORTED) sorted else draw
      val pin = LabL1MayJuneOwnerAttestedBytePair.pinnedRole(role)
      assertEquals(pin.first, actual["sourceBytes"])
      assertEquals(pin.second, actual["sourceSha256"])
      assertEquals(LabL1PeriodSourceIdentity.mayJunePeriod, actual["period"])
      assertEquals(LabL1PeriodSourceIdentity.cloud500Tier, actual["tier"])
      assertEquals(LabL1PeriodSourceIdentity.parserVersion, actual["parserVersion"])
    }
    assertNotEquals(sorted["sourceSha256"], draw["sourceSha256"])
    assertNotEquals(sorted["sourceBytes"], draw["sourceBytes"])
  }

  @Test fun wrongRoleOrMissingSessionFailsClosed() {
    assertThrows(IllegalArgumentException::class.java) {
      LabL1PdfiumTokenResponse.fromVerifiedPage(
        "session", null, 1, 2, "AB12345678", receipt(LabL1MayJuneDualPdfOracle.Role.SORTED))
    }
    assertThrows(IllegalArgumentException::class.java) {
      LabL1PdfiumTokenResponse.fromVerifiedPage(
        "", LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER, 1, 2, "AB12345678", receipt(LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER))
    }
  }

  @Test fun invalidPageAndBlankExtractionFailClosed() {
    val role = LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER
    for (page in listOf(0, 3)) {
      assertThrows(IllegalArgumentException::class.java) {
        LabL1PdfiumTokenResponse.fromVerifiedPage("session", role, page, 2, "AB12345678", receipt(role))
      }
    }
    assertThrows(IllegalArgumentException::class.java) {
      LabL1PdfiumTokenResponse.fromVerifiedPage("session", role, 1, 2, "   ", receipt(role))
    }
  }

  @Test fun swappedRoleAndTamperedSnapshotReceiptFailClosed() {
    val sorted = LabL1MayJuneDualPdfOracle.Role.SORTED
    val draw = LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER
    val good = receipt(sorted)
    for (bad in listOf(receipt(draw), good.copy(bytes = good.bytes + 1),
      good.copy(sha256 = "0".repeat(64)))) {
      assertThrows(IllegalArgumentException::class.java) {
        LabL1PdfiumTokenResponse.fromVerifiedPage(
          "verified-session", sorted, 1, 2, "AB12345678", bad)
      }
    }
  }

  @Test fun embeddedPartialInvoiceIsNeverReturned() {
    val response = LabL1PdfiumTokenResponse.fromVerifiedPage(
      "session", LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER,
      1, 1, "XAB12345678 AB123456789", receipt(LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER))
    )
    assertEquals(emptyList<String>(), response["tokens"])
  }
}
