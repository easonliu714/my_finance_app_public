package me.movenext.flutter_pdf_text

import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class LabL1MayJuneSourceCustodyTest {
  private fun sample(origin: LabL1MayJuneSourceCustody.Origin) =
    LabL1MayJuneSourceCustody.Evidence(
      origin, "115-05-06", "cloud-500", 119769589L, "a".repeat(64),
      146461156L, "b".repeat(64)
    )

  @Test fun ownerAndHttpsRemainDistinctUnpinnedEvidence() {
    val custody = LabL1MayJuneSourceCustody
    assertEquals(LabL1MayJuneSourceCustody.Status.OWNER_BYTES_VERIFIED_NOT_OFFICIAL_PIN,
      custody.classify(sample(LabL1MayJuneSourceCustody.Origin.OWNER_SUPPLIED)))
    assertEquals(LabL1MayJuneSourceCustody.Status.HTTPS_BYTES_VERIFIED_NOT_OFFICIAL_PIN,
      custody.classify(sample(LabL1MayJuneSourceCustody.Origin.HTTPS_STREAM)))
  }

  @Test fun invalidRolePairsCannotBecomeEvidence() {
    val custody = LabL1MayJuneSourceCustody
    val valid = sample(LabL1MayJuneSourceCustody.Origin.OWNER_SUPPLIED)
    for (invalid in listOf(
      valid.copy(period = "115-07-08"),
      valid.copy(tier = "cloud-800"),
      valid.copy(sortedBytes = 0L),
      valid.copy(drawBytes = -1L),
      valid.copy(sortedSha256 = "bad"),
      valid.copy(drawSha256 = valid.sortedSha256),
      valid.copy(drawSha256 = "A".repeat(64))
    )) {
      assertEquals(LabL1MayJuneSourceCustody.Status.INVALID_EVIDENCE, custody.classify(invalid))
    }
  }

  @Test fun noEvidenceOriginCanGrantOfficialAuthority() {
    val custody = LabL1MayJuneSourceCustody
    for (origin in LabL1MayJuneSourceCustody.Origin.values()) {
      try {
        custody.requireOfficialAuthority(sample(origin))
        fail("Must fail closed")
      } catch (error: IllegalStateException) {
        assertEquals("L1_PERIOD_SOURCE_UNPINNED", error.message)
      }
    }
  }
}
