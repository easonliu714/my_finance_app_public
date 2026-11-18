package me.movenext.flutter_pdf_text

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class LabL1PdfiumTokenResponseTest {
  @Test fun nativePageProducesBoundedRoleTaggedTokens() {
    val actual = LabL1PdfiumTokenResponse.fromVerifiedPage(
      "verified-session", LabL1MayJuneDualPdfOracle.Role.SORTED,
      2, 3, "AB12345678 CD87654321"
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
      "sorted-session", LabL1MayJuneDualPdfOracle.Role.SORTED, 1, 2, "AB12345678")
    val draw = LabL1PdfiumTokenResponse.fromVerifiedPage(
      "draw-session", LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER, 1, 2, "AB12345678")
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
        "session", null, 1, 2, "AB12345678")
    }
    assertThrows(IllegalArgumentException::class.java) {
      LabL1PdfiumTokenResponse.fromVerifiedPage(
        "", LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER, 1, 2, "AB12345678")
    }
  }

  @Test fun invalidPageAndBlankExtractionFailClosed() {
    val role = LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER
    for (page in listOf(0, 3)) {
      assertThrows(IllegalArgumentException::class.java) {
        LabL1PdfiumTokenResponse.fromVerifiedPage("session", role, page, 2, "AB12345678")
      }
    }
    assertThrows(IllegalArgumentException::class.java) {
      LabL1PdfiumTokenResponse.fromVerifiedPage("session", role, 1, 2, "   ")
    }
  }

  @Test fun embeddedPartialInvoiceIsNeverReturned() {
    val response = LabL1PdfiumTokenResponse.fromVerifiedPage(
      "session", LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER,
      1, 1, "XAB12345678 AB123456789"
    )
    assertEquals(emptyList<String>(), response["tokens"])
  }
}
