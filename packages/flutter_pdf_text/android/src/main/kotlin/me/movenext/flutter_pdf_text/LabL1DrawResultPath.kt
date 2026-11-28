package me.movenext.flutter_pdf_text

import java.io.File
import java.nio.file.Files

/** Lab draw-page receipt admission; no writes, directory creation or deletion. */
internal object LabL1DrawResultPath {
  private val requestPattern = Regex("^[0-9]{1,24}$")

  fun requireNew(filesRoot: File, path: String, requestId: String): File {
    fun invalid(): Nothing = throw IllegalStateException("L1_OWNER_DRAW_RESULT_PATH_INVALID")
    if (!requestPattern.matches(requestId) || path.isBlank()) invalid()
    val lab = File(filesRoot.canonicalFile, "issue13_cloud500_diag")
    if (!lab.isDirectory || lab.canonicalFile != lab || Files.isSymbolicLink(lab.toPath())) invalid()
    val supplied = File(path)
    if (!supplied.isAbsolute || supplied.name != "platform_probe_$requestId.json" ||
        supplied.parentFile?.canonicalFile != lab) invalid()
    val target = File(lab, supplied.name)
    // A receipt is per request; never overwrite an old or linked result.
    if (target.exists() || Files.isSymbolicLink(target.toPath()) ||
        target.canonicalFile != target) invalid()
    return target
  }
}
