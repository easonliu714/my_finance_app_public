package me.movenext.flutter_pdf_text

/**
 * Lab-only admission for extracting real PDFium page text. A generic session,
 * unknown role, or role-swapped session cannot be used as a role-bound probe.
 * This is not a source authenticity proof or production award authorization.
 */
internal object LabL1RoleSessionGuard {
  fun allows(
    registered: LabL1MayJuneDualPdfOracle.Role?,
    requested: LabL1MayJuneDualPdfOracle.Role?
  ): Boolean = registered != null && requested != null && registered == requested
}
