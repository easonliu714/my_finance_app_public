package me.movenext.flutter_pdf_text

/** Lab-only native PDFium page response; never formal award evidence. */
internal object LabL1PdfiumTokenResponse {
  fun fromVerifiedPage(
    sessionId: String,
    role: LabL1MayJuneDualPdfOracle.Role?,
    pageNumber: Int,
    pageCount: Int,
    text: String,
    verifiedSnapshot: LabL1VerifiedPdfSnapshot.Expected
  ): Map<String, Any> {
    require(sessionId.isNotBlank() && role != null) { "L1_ROLE_SESSION_MISMATCH_HOLD" }
    require(pageCount in 1..100_000 && pageNumber in 1..pageCount) {
      "L1_PAGE_BOUNDS_HOLD"
    }
    require(text.isNotBlank()) { "L1_PAGE_EXTRACTION_EMPTY_HOLD" }
    // The role comes from the plugin's verified-session registry, not Flutter.
    // These immutable Owner-attested pins are diagnostic identity hints only;
    // they do not independently attest MOF bytes or authorize an Oracle result.
    val pinned = LabL1MayJuneOwnerAttestedBytePair.pinnedRole(role)
    // Compare the receipt captured from the SHA-verified unlinked inode, not
    // only a role label or caller-supplied expected metadata.
    require(verifiedSnapshot.role == role &&
      verifiedSnapshot.bytes == pinned.first &&
      verifiedSnapshot.sha256 == pinned.second) { "L1_SESSION_SNAPSHOT_RECEIPT_MISMATCH_HOLD" }
    // Reject untrusted role/receipt mismatches before parsing potentially large PDFium text.
    val tokens = LabL1PageTokenExtractor.extract(text)
    return mapOf(
      "sessionId" to sessionId,
      "role" to (if (role == LabL1MayJuneDualPdfOracle.Role.SORTED)
        "sorted" else "draw_order"),
      "sourceBytes" to verifiedSnapshot.bytes,
      "sourceSha256" to verifiedSnapshot.sha256,
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
