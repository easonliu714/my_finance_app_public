package me.movenext.flutter_pdf_text

/**
 * Lab-only period and tier authority for an already byte-pinned official PDF.
 * Discovering a publication URL never promotes it to a pinned source.
 */
internal object LabL1PeriodSourceIdentity {
  const val julyAugustPeriod = "115-07-08"
  const val mayJunePeriod = "115-05-06"
  const val cloud500Tier = "cloud-500"
  const val parserVersion = "pdf-renderer-l1-v1"

  data class Pinned(
    val period: String,
    val tier: String,
    val bytes: Long,
    val sha256: String,
    val parserVersion: String
  ) {
    /** Storage keys cannot be reused between different periods or sources. */
    fun storageNamespace(): String =
      listOf(period, tier, sha256, parserVersion).joinToString("_")
  }

  fun requirePinned(
    period: String,
    tier: String,
    observedSha256: String? = null
  ): Pinned {
    if (tier != cloud500Tier) {
      throw IllegalStateException("L1_SOURCE_TIER_UNSUPPORTED")
    }
    // May-June official sorted PDF URI has been discovered, but its exact
    // bytes and SHA-256 have NOT been independently obtained or pinned.
    // Never substitute the July-August source or its durable cursor.
    if (period == mayJunePeriod) {
      throw IllegalStateException("L1_PERIOD_SOURCE_UNPINNED")
    }
    if (period != julyAugustPeriod) {
      throw IllegalStateException("L1_SOURCE_PERIOD_UNSUPPORTED")
    }
    val pinned = Pinned(
      period = julyAugustPeriod,
      tier = cloud500Tier,
      bytes = LabOfficialPdfPreflight.OFFICIAL_BYTES,
      sha256 = LabOfficialPdfPreflight.OFFICIAL_SHA256,
      parserVersion = parserVersion
    )
    if (observedSha256 != null && observedSha256 != pinned.sha256) {
      throw IllegalStateException("L1_PERIOD_SOURCE_SHA_MISMATCH")
    }
    return pinned
  }
}
