package me.movenext.flutter_pdf_text

/**
 * Lab-only resource evidence for the isolated platform PDF worker.
 * PSS and RSS are kB samples, never proof of a native process exit.
 * Missing or malformed metrics must stay UNKNOWN, not zero or PASS.
 */
internal object LabL1NativeMemoryEvidence {
  private val vmRssPattern = Regex("""^VmRSS:\s*([0-9]+)\s+kB\s*$""")

  fun rssKbFromProcStatus(status: String): Long? {
    for (line in status.lineSequence()) {
      if (!line.startsWith("VmRSS:")) continue
      val value = vmRssPattern.matchEntire(line)?.groupValues?.get(1)
        ?.toLongOrNull()
      return value?.takeIf { it > 0L }
    }
    return null
  }

  fun format(pssKb: Int?, rssKb: Long?): String {
    val pss = pssKb?.takeIf { it > 0 }?.toString() ?: "UNKNOWN"
    val rss = rssKb?.takeIf { it > 0L }?.toString() ?: "UNKNOWN"
    return "native_pss_kb=$pss native_rss_kb=$rss native_process_exit=UNKNOWN"
  }
}
