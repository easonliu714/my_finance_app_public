package me.movenext.flutter_pdf_text

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Synthetic lifecycle tests; NOT real PDF parser or Owner device evidence. */
class LabL1ParserSessionLifecycleTest {
  private val sorted = LabL1ParserSessionLifecycle.Role.SORTED
  private val draw = LabL1ParserSessionLifecycle.Role.DRAW_ORDER

  @Test fun requiresTwoDistinctLiveRoleBoundSessions() {
    val gate = LabL1ParserSessionLifecycle()
    assertFalse(gate.isActivePair("s", "d"))
    assertTrue(gate.register(sorted, "s"))
    assertFalse(gate.isActivePair("s", "d"))
    assertFalse(gate.register(draw, "s"))
    assertTrue(gate.register(draw, "d"))
    assertTrue(gate.isActivePair("s", "d"))
    assertFalse(gate.isActivePair("d", "s"))
    assertFalse(gate.isActivePair("s", "s"))
  }

  @Test fun replacementReopenAndCloseAreFailClosed() {
    val gate = LabL1ParserSessionLifecycle()
    assertTrue(gate.register(sorted, "s"))
    assertTrue(gate.register(draw, "d"))
    assertFalse(gate.register(sorted, "replacement"))
    assertFalse(gate.close(draw, "wrong"))
    assertTrue(gate.close(draw, "d"))
    assertFalse(gate.isActivePair("s", "d"))
    assertTrue(gate.register(draw, "d2"))
    assertFalse(gate.isActivePair("s", "d"))
    assertTrue(gate.isActivePair("s", "d2"))
    gate.invalidate()
    assertFalse(gate.isActivePair("s", "d2"))
    assertFalse(gate.register(sorted, "s3"))
    assertFalse(gate.close(sorted, "s"))
  }

  @Test fun rejectsBlankAndDuplicateIdentifiers() {
    val gate = LabL1ParserSessionLifecycle()
    assertFalse(gate.register(sorted, ""))
    assertFalse(gate.register(draw, "  "))
    assertTrue(gate.register(sorted, "one"))
    assertFalse(gate.register(draw, "one"))
  }
}
