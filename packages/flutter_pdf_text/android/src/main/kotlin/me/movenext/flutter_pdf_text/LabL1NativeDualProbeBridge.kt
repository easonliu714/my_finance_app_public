package me.movenext.flutter_pdf_text

/**
 * Lab-only boundary from TWO actual native PDFium page-token responses to the
 * existing dual-source Oracle. The plugin, not Flutter, owns both responses.
 * No bounded page hit may become a formal award or an absence decision.
 */
internal object LabL1NativeDualProbeBridge {
  private val full10 = Regex("[A-Z]{2}[0-9]{8}")
  fun positive(
    candidate: String,
    drawSession: String,
    sortedSession: String,
    nativePages: Map<String, Map<String, Any>>,
    roles: Map<String, LabL1MayJuneDualPdfOracle.Role>,
    receipts: Map<String, LabL1VerifiedPdfSnapshot.Expected>,
    liveSessions: Set<String>
  ): LabL1MayJuneDualPdfOracle.Outcome {
    fun hold() = LabL1MayJuneDualPdfOracle.Outcome.Hold("L1_NATIVE_DUAL_SESSION_HOLD")
    if (!full10.matches(candidate) || drawSession.isBlank() || sortedSession.isBlank() ||
        drawSession == sortedSession || !liveSessions.containsAll(listOf(drawSession, sortedSession)) ||
        roles[drawSession] != LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER ||
        roles[sortedSession] != LabL1MayJuneDualPdfOracle.Role.SORTED) return hold()
    fun probe(id: String, role: LabL1MayJuneDualPdfOracle.Role): LabL1MayJuneDualPdfOracle.Probe? {
      val page = nativePages[id] ?: return null
      val receipt = receipts[id] ?: return null
      val pin = LabL1MayJuneOwnerAttestedBytePair.pinnedRole(role)
      val roleName = if (role == LabL1MayJuneDualPdfOracle.Role.SORTED) "sorted" else "draw_order"
      val uri = if (role == LabL1MayJuneDualPdfOracle.Role.SORTED)
        LabL1MayJuneDualPdfOracle.sortedUri else LabL1MayJuneDualPdfOracle.drawOrderUri
      if (receipt.role != role || receipt.bytes != pin.first || receipt.sha256 != pin.second ||
          page["sessionId"] != id || page["role"] != roleName ||
          page["sourceBytes"] != receipt.bytes || page["sourceSha256"] != receipt.sha256 ||
          page["period"] != LabL1PeriodSourceIdentity.mayJunePeriod ||
          page["tier"] != LabL1PeriodSourceIdentity.cloud500Tier ||
          page["parserVersion"] != LabL1PeriodSourceIdentity.parserVersion ||
          page["authority"] != "LAB_PDFIUM_PAGE_TOKENS_ONLY" ||
          page["extractionComplete"] != true) return null
      val number = page["pageNumber"] as? Int ?: return null
      val count = page["pageCount"] as? Int ?: return null
      // The pinned official 115-05-06 PDFs each contain exactly 77,000 pages.
      // A truncated/replaced document must never yield a diagnostic positive.
      if (count != LabL1MayJuneOwnerAttestedBytePair.expectedPageCount ||
          number !in 1..count) return null
      val raw = page["tokens"] as? List<*> ?: return null
      if (raw.size !in 1..50 || raw.any { it !is String }) return null
      val tokens = raw.filterIsInstance<String>()
      if (tokens.any { !full10.matches(it) } || tokens.distinct().size != tokens.size ||
          candidate !in tokens) return null
      val source = LabL1MayJuneDualPdfOracle.Source(
        LabL1PeriodSourceIdentity.mayJunePeriod, LabL1PeriodSourceIdentity.cloud500Tier,
        role, uri, receipt.bytes, receipt.sha256, LabL1PeriodSourceIdentity.parserVersion
      )
      return LabL1MayJuneDualPdfOracle.Probe(
        source, candidate, true, number, candidate, tokens, count, 1, true
      )
    }
    val draw = probe(drawSession, LabL1MayJuneDualPdfOracle.Role.DRAW_ORDER) ?: return hold()
    val sorted = probe(sortedSession, LabL1MayJuneDualPdfOracle.Role.SORTED) ?: return hold()
    return LabL1MayJuneDualPdfOracle.positive(draw, sorted) { source ->
      val id = if (source.role == LabL1MayJuneDualPdfOracle.Role.SORTED) sortedSession else drawSession
      val receipt = receipts[id]
      receipt != null && receipt.role == source.role &&
        receipt.bytes == source.bytes && receipt.sha256 == source.sha256 &&
        liveSessions.contains(id) && roles[id] == source.role
    }
  }
}
