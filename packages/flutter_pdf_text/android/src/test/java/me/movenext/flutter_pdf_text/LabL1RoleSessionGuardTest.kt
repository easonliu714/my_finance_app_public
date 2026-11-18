package me.movenext.flutter_pdf_text

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LabL1RoleSessionGuardTest {
  @Test fun exactRoleAllowedOnly() {
    val sorted = LabL1MayJuneDualPdfOracle.Role.SORTED
    val draw = LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER
    assertTrue(LabL1RoleSessionGuard.allows(sorted, sorted))
    assertTrue(LabL1RoleSessionGuard.allows(draw, draw))
    assertFalse(LabL1RoleSessionGuard.allows(sorted, draw))
    assertFalse(LabL1RoleSessionGuard.allows(draw, sorted))
  }

  @Test fun unknownOrClosedSessionFailsClosed() {
    val sorted = LabL1MayJuneDualPdfOracle.Role.SORTED
    assertFalse(LabL1RoleSessionGuard.allows(null, sorted))
    assertFalse(LabL1RoleSessionGuard.allows(sorted, null))
    assertFalse(LabL1RoleSessionGuard.allows(null, null))
  }
  @Test fun genericReadCannotBypassRoleCustody() {
    assertTrue(LabL1RoleSessionGuard.allowsGenericRead(null))
    assertFalse(LabL1RoleSessionGuard.allowsGenericRead(
      LabL1MayJuneDualPdfOracle.Role.SORTED))
    assertFalse(LabL1RoleSessionGuard.allowsGenericRead(
      LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER))
  }
}
