package me.movenext.flutter_pdf_text

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LabL1NativeMemoryEvidenceTest {
  @Test fun parsesExactProcVmRssKilobytes() {
    val status = "Name:\tplatform_pdf\nVmSize:\t123456 kB\nVmRSS:\t4096 kB\n"
    assertEquals(4096L, LabL1NativeMemoryEvidence.rssKbFromProcStatus(status))
  }

  @Test fun malformedMissingAndOverflowRssRemainUnknown() {
    assertNull(LabL1NativeMemoryEvidence.rssKbFromProcStatus("VmSize: 9 kB"))
    assertNull(LabL1NativeMemoryEvidence.rssKbFromProcStatus("VmRSS: -1 kB"))
    assertNull(LabL1NativeMemoryEvidence.rssKbFromProcStatus("VmRSS: 100 MB"))
    assertNull(LabL1NativeMemoryEvidence.rssKbFromProcStatus("VmRSS: 0 kB"))
    assertNull(LabL1NativeMemoryEvidence.rssKbFromProcStatus(
      "VmRSS: 9999999999999999999999999999999999999 kB"))
  }

  @Test fun observedMemoryNeverClaimsNativeProcessExit() {
    val observed = LabL1NativeMemoryEvidence.format(1234, 5678L)
    assertEquals(
      "native_pss_kb=1234 native_rss_kb=5678 native_process_exit=UNKNOWN",
      observed)
    val missing = LabL1NativeMemoryEvidence.format(null, null)
    assertEquals(
      "native_pss_kb=UNKNOWN native_rss_kb=UNKNOWN native_process_exit=UNKNOWN",
      missing)
    assertTrue(LabL1NativeMemoryEvidence.format(-1, -5L)
      .contains("native_pss_kb=UNKNOWN native_rss_kb=UNKNOWN"))
  }
}
