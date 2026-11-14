package me.movenext.flutter_pdf_text

/**
 * Diagnostic-only source custody for the May-June dual-PDF pair.
 * Role labels are declarations, not PDF content verification or an official pin.
 * Neither an owner-uploaded digest nor an HTTPS download grants posting authority.
 */
internal object LabL1MayJuneSourceCustody {
  enum class Origin { OWNER_SUPPLIED, HTTPS_STREAM }
  enum class Role { SORTED, DRAW_ORDER }
  enum class Status {
    INVALID_EVIDENCE,
    OWNER_BYTES_VERIFIED_NOT_OFFICIAL_PIN,
    HTTPS_BYTES_VERIFIED_NOT_OFFICIAL_PIN
  }

  data class Evidence(
    val origin: Origin,
    val period: String,
    val tier: String,
    val sortedRole: Role,
    val sortedBytes: Long,
    val sortedSha256: String,
    val drawRole: Role,
    val drawBytes: Long,
    val drawSha256: String
  )

  fun classify(evidence: Evidence): Status {
    val sha = Regex("[0-9a-f]{64}")
    if (evidence.period != LabL1PeriodSourceIdentity.mayJunePeriod ||
        evidence.tier != LabL1PeriodSourceIdentity.cloud500Tier ||
        evidence.sortedRole != Role.SORTED ||
        evidence.drawRole != Role.DRAW_ORDER ||
        evidence.sortedBytes <= 0L || evidence.drawBytes <= 0L ||
        !sha.matches(evidence.sortedSha256) ||
        !sha.matches(evidence.drawSha256) ||
        evidence.sortedSha256 == evidence.drawSha256) {
      return Status.INVALID_EVIDENCE
    }
    return when (evidence.origin) {
      Origin.OWNER_SUPPLIED -> Status.OWNER_BYTES_VERIFIED_NOT_OFFICIAL_PIN
      Origin.HTTPS_STREAM -> Status.HTTPS_BYTES_VERIFIED_NOT_OFFICIAL_PIN
    }
  }

  fun requireOfficialAuthority(evidence: Evidence): Nothing {
    classify(evidence)
    throw IllegalStateException("L1_PERIOD_SOURCE_UNPINNED")
  }
}
