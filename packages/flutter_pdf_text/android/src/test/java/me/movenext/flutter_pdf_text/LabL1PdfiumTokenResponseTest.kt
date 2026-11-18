package me.movenext.flutter_pdf_text

import org.junit.Assert.assertEquals
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
