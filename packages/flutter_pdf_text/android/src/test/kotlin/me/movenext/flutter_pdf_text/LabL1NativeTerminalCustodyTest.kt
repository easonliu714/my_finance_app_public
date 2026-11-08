package me.movenext.flutter_pdf_text

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.fail
import org.junit.Test

class LabL1NativeTerminalCustodyTest {
  @Test fun successfulClosePrecedesTerminalPublication() {
    val events = mutableListOf<String>()
    LabL1NativeTerminalCustody.publishAfterClose(
      closeResources = { events.add("renderer_closed") },
      publishSuccess = { events.add("terminal_success") }
    )
    assertEquals(listOf("renderer_closed", "terminal_success"), events)
  }

  @Test fun failedCloseCannotPublishSuccess() {
    var published = false
    try {
      LabL1NativeTerminalCustody.publishAfterClose(
        closeResources = { throw IllegalStateException("NATIVE_RENDERER_CLOSE_FAILED") },
        publishSuccess = { published = true }
      )
      fail("close failure must propagate")
    } catch (error: IllegalStateException) {
      assertEquals("NATIVE_RENDERER_CLOSE_FAILED", error.message)
    }
    assertFalse(published)
  }
}
