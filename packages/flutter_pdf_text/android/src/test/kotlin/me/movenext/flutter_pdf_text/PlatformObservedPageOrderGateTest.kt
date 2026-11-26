package me.movenext.flutter_pdf_text

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** C26 deterministic JVM synthetic page samples; NOT 87K global proof or Android runtime. */
class PlatformObservedPageOrderGateTest {
  @Test fun sampledOrderedPagesPassInAnyVisitOrder() {
    val gate = PlatformObservedPageOrderGate(87000)
    assertTrue(gate.observe(87000, listOf("ZZ99999999")))
    assertTrue(gate.observe(1, listOf("AA00000001", "AB00000001")))
    assertTrue(gate.observe(43500, listOf("BC00000001", "BD00000001")))
    assertTrue(gate.observe(43500, listOf("BC00000001", "BD00000001")))
  }

  @Test fun nonAdjacentCrossPageInversionFailsClosed() {
    val gate = PlatformObservedPageOrderGate(87000)
    assertTrue(gate.observe(1, listOf("CC00000001")))
    assertFalse(gate.observe(87000, listOf("BB00000001")))
  }

  @Test fun insertionBetweenObservedPagesChecksBothNeighbors() {
    val gate = PlatformObservedPageOrderGate(87000)
    assertTrue(gate.observe(1, listOf("AA00000001")))
    assertTrue(gate.observe(87000, listOf("CC00000001")))
    assertFalse(gate.observe(43500, listOf("DD00000001")))
    assertTrue(gate.observe(43500, listOf("BB00000001")))
  }

  @Test fun malformedPageAndChangedSampleBoundsFailClosed() {
    val gate = PlatformObservedPageOrderGate(87000)
    assertFalse(gate.observe(0, listOf("AA00000001")))
    assertFalse(gate.observe(87001, listOf("AA00000001")))
    assertFalse(gate.observe(1, emptyList()))
    assertFalse(gate.observe(1, listOf("BB00000001", "AA00000001")))
    assertTrue(gate.observe(1, listOf("AA00000001", "AB00000001")))
    assertFalse(gate.observe(1, listOf("AA00000001", "AC00000001")))
  }

  @Test fun equalBoundaryAcrossAdjacentPagesIsNotFalseInversion() {
    val gate = PlatformObservedPageOrderGate(87000)
    assertTrue(gate.observe(1, listOf("AB00000001")))
    assertTrue(gate.observe(2, listOf("AB00000001", "AC00000001")))
  }

  /** C27: two PDFium reads with identical bounds but different interior rows
   * must never be treated as one stable observed page. JVM only, not device. */
  @Test fun revisitedPageWithSameBoundsButChangedInteriorFailsClosed() {
    val gate = PlatformObservedPageOrderGate(87000)
    val first = listOf("AA00000001", "AB00000001", "AC00000001")
    assertTrue(gate.observe(43500, first))
    assertFalse(gate.observe(43500,
      listOf("AA00000001", "AB00000002", "AC00000001")))
    assertTrue(gate.observe(43500, first))
    assertFalse(gate.observe(43500,
      listOf("AA00000001", "AC00000001")))
  }

  /** C27: a caller mutating a list after observe() cannot rewrite the
   * authority's stored observation. */
  @Test fun callerListMutationCannotRewritePreviouslyObservedPage() {
    val gate = PlatformObservedPageOrderGate(87000)
    val mutable = mutableListOf("AA00000001", "AB00000001", "AC00000001")
    assertTrue(gate.observe(1, mutable))
    mutable[1] = "AB00000002"
    assertFalse(gate.observe(1, mutable))
    assertTrue(gate.observe(1,
      listOf("AA00000001", "AB00000001", "AC00000001")))
    assertTrue(gate.observe(2, listOf("AC00000001", "AD00000001")))
  }
}
