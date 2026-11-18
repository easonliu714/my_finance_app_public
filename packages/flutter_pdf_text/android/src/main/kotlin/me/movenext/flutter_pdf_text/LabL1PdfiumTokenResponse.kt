package me.movenext.flutter_pdf_text

/** Lab-only native PDFium page response; never formal award evidence. */
internal object LabL1PdfiumTokenResponse {
  fun fromVerifiedPage(
    sessionId: String,
    role: LabL1MayJuneDualPdfOracle.Role?,
    pageNumber: Int,
    pageCount: Int,
    text: String
  ): Map<String, Any> {
    require(sessionId.isNotBlank() && role != null) { "L1_ROLE_SESSION_MISMATCH_HOLD" }
    require(pageCount in 1..100_000 && pageNumber in 1..pageCount) {
      "L1_PAGE_BOUNDS_HOLD"
    }
    require(text.isNotBlank()) { "L1_PAGE_EXTRACTION_EMPTY_HOLD" }
    val tokens = LabL1PageTokenExtractor.extract(text)
    // The role comes from the plugin's verified-session registry, not Flutter.
    // These immutable Owner-attested pins are diagnostic identity hints only;
    // they do not independently attest MOF bytes or authorize an Oracle result.
    val pinned = LabL1MayJuneOwnerAttestedBytePair.pinnedRole(role)
    return mapOf(
      "sessionId" to sessionId,
      "role" to (if (role == LabL1MayJuneDualPdfOracle.Role.SORTED)
        "sorted" else "draw_order"),
      "sourceBytes" to pinned.first,
      "sourceSha256" to pinned.second,
      "period" to LabL1PeriodSourceIdentity.mayJunePeriod,
      "tier" to LabL1PeriodSourceIdentity.cloud500Tier,
      "parserVersion" to LabL1PeriodSourceIdentity.parserVersion,
      "pageNumber" to pageNumber,
      "pageCount" to pageCount,
      "extractionComplete" to true,
      "tokens" to tokens,
      "authority" to "LAB_PDFIUM_PAGE_TOKENS_ONLY"
    )
  }
}
