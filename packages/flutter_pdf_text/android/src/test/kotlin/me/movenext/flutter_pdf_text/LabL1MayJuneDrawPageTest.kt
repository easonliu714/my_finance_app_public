package me.movenext.flutter_pdf_text

import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

/** Synthetic fixtures; no official winner, real PDF or device claim. */
class LabL1MayJuneDrawPageTest {
  private val api = LabL1MayJuneDrawPage
  private val tokens = (49 downTo 0).map { "AB%08d".format(java.util.Locale.ROOT, it) }

  private fun rejects(reason: String, action: () -> Unit) {
    try {
      action()
      fail("Expected $reason")
    } catch (error: IllegalStateException) {
      assertEquals(reason, error.message)
    }
  }

  @Test fun explicitPageCommandIsBoundedAndDoesNotCaptureOtherOperations() {
    assertEquals(1, api.requestedPage("LAB_MAY_JUNE_DRAW_PAGE:1"))
    assertEquals(77000, api.requestedPage("LAB_MAY_JUNE_DRAW_PAGE:77000"))
    assertEquals(null, api.requestedPage("LAB_MAY_JUNE_OPEN:draw_order"))
    assertEquals(null, api.requestedPage("LAB_L1_EXPORT:1"))
    for (raw in listOf("", "0", "01", "-1", "77001", "100000", "1:sorted", " 1")) {
      rejects("L1_OWNER_DRAW_PAGE_INVALID") { api.requestedPage("LAB_MAY_JUNE_DRAW_PAGE:$raw") }
    }
  }

  @Test fun completeFull10PagePreservesDrawOrderIncludingSpacedDigits() {
    assertEquals(tokens, api.extract(tokens.joinToString("\n")))
    val spaced = tokens.map { it.take(2) + " " + it.drop(2).toList().joinToString(" ") }
    assertEquals(tokens, api.extract(spaced.joinToString("\n")))
  }

  @Test fun incompleteDuplicateEmbeddedAndOversizedPagesHold() {
    val invalid = listOf(
      tokens.dropLast(1),
      tokens + "AB00000050",
      tokens.dropLast(1) + tokens.first(),
      tokens.dropLast(1) + ("字" + tokens.last()),
      tokens.dropLast(1) + (tokens.last() + "\u0301"),
      tokens.dropLast(1) + tokens.last().dropLast(1)
    )
    for (page in invalid) {
      rejects("L1_OWNER_DRAW_PAGE_INCOMPLETE_HOLD") { api.extract(page.joinToString("\n")) }
    }
    rejects("L1_OWNER_DRAW_TEXT_BUDGET_HOLD") { api.extract("X".repeat(api.maxTextChars + 1)) }
  }
}
