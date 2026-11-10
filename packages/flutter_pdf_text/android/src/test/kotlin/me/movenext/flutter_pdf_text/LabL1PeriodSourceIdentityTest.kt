package me.movenext.flutter_pdf_text

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class LabL1PeriodSourceIdentityTest {
  private fun rejects(reason: String, block: () -> Unit) {
    try {
      block()
      fail("Expected $reason")
    } catch (error: IllegalStateException) {
      assertEquals(reason, error.message)
    }
  }

  @Test fun julyAugustUsesOnlyItsExistingBytePin() {
    val source = LabL1PeriodSourceIdentity.requirePinned("115-07-08", "cloud-500")
    assertEquals(135200798L, source.bytes)
    assertEquals(LabOfficialPdfPreflight.OFFICIAL_SHA256, source.sha256)
    assertEquals("115-07-08", source.period)
  }

  @Test fun mayJuneRemainsUnpinnedEvenWhenOldShaIsPresented() {
    rejects("L1_PERIOD_SOURCE_UNPINNED") {
      LabL1PeriodSourceIdentity.requirePinned(
        "115-05-06", "cloud-500", LabOfficialPdfPreflight.OFFICIAL_SHA256)
    }
  }

  @Test fun wrongTierCannotReuseCloud500Pin() {
    rejects("L1_SOURCE_TIER_UNSUPPORTED") {
      LabL1PeriodSourceIdentity.requirePinned("115-07-08", "cloud-800")
    }
  }

  @Test fun unsupportedPeriodNeverFallsBackToCurrentSource() {
    rejects("L1_SOURCE_PERIOD_UNSUPPORTED") {
      LabL1PeriodSourceIdentity.requirePinned("115-03-04", "cloud-500")
    }
  }

  @Test fun changedOrMalformedObservedShaFailsClosed() {
    for (sha in listOf("0".repeat(64), "bad", "")) {
      rejects("L1_PERIOD_SOURCE_SHA_MISMATCH") {
        LabL1PeriodSourceIdentity.requirePinned("115-07-08", "cloud-500", sha)
      }
    }
  }

  @Test fun namespaceBindsPeriodTierShaAndParserVersion() {
    val pinned = LabL1PeriodSourceIdentity.requirePinned("115-07-08", "cloud-500")
    val key = pinned.storageNamespace()
    assertTrue(key.contains("115-07-08_cloud-500_"))
    assertTrue(key.contains(pinned.sha256))
    assertTrue(key.endsWith(LabL1PeriodSourceIdentity.parserVersion))
    assertFalse(key.contains("115-05-06"))
  }
}
