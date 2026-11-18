package me.movenext.flutter_pdf_text

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.ConcurrentHashMap

class LabL1NativeSessionAdmissionTest {
  private val sorted = LabL1MayJuneDualPdfOracle.Role.SORTED
  private val draw = LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER
  private val documents = ConcurrentHashMap<String, Any>()
  private val paths = ConcurrentHashMap<String, String>()
  private val roles = ConcurrentHashMap<String, LabL1MayJuneDualPdfOracle.Role>()
  private val receipts = ConcurrentHashMap<String, LabL1VerifiedPdfSnapshot.Expected>()
  private fun receipt(role: LabL1MayJuneDualPdfOracle.Role) =
    LabL1VerifiedPdfSnapshot.Expected(role, 100L, "a".repeat(64))
  private fun admit(id: String, role: LabL1MayJuneDualPdfOracle.Role,
                    evidence: LabL1VerifiedPdfSnapshot.Expected = receipt(role)) =
    LabL1NativeSessionAdmission.register(
      id, role, evidence, Any(), documents, paths, roles, receipts
    )
  private fun held(action: () -> Unit) {
    try { action(); fail("expected fail closed") }
    catch (e: IllegalArgumentException) {
      assertEquals("L1_NATIVE_SESSION_ADMISSION_HOLD", e.message)
    }
  }

  @Test fun twoDistinctRoleBoundSessionsAdmitted() {
    admit("sorted-session", sorted)
    admit("draw-session", draw)
    assertEquals(2, documents.size)
    assertEquals(sorted, roles["sorted-session"])
    assertEquals(draw, roles["draw-session"])
  }

  @Test fun sameRoleReplayCannotReplaceOriginalCustody() {
    admit("first", sorted)
    held { admit("second", sorted) }
    assertEquals(setOf("first"), documents.keys)
    assertEquals(setOf("first"), receipts.keys)
  }

  @Test fun sameSessionReplayAcrossRolesRejectedWithoutPartialInsertion() {
    admit("shared", sorted)
    held { admit("shared", draw) }
    assertEquals(sorted, roles["shared"])
    assertEquals(1, documents.size)
  }

  @Test fun swappedReceiptRejectedWithoutCreatingSession() {
    held { admit("wrong", draw, receipt(sorted)) }
    assertTrue(documents.isEmpty())
    assertTrue(paths.isEmpty())
    assertTrue(roles.isEmpty())
    assertTrue(receipts.isEmpty())
  }
}
