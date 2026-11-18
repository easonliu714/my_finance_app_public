package me.movenext.flutter_pdf_text

import java.util.concurrent.ConcurrentHashMap

/** Lab-only atomic custody admission; caller closes native document on failure. */
internal object LabL1NativeSessionAdmission {
  fun <T : Any> register(
    id: String,
    role: LabL1MayJuneDualPdfOracle.Role,
    receipt: LabL1VerifiedPdfSnapshot.Expected,
    document: T,
    documents: ConcurrentHashMap<String, T>,
    paths: ConcurrentHashMap<String, String>,
    roles: ConcurrentHashMap<String, LabL1MayJuneDualPdfOracle.Role>,
    receipts: ConcurrentHashMap<String, LabL1VerifiedPdfSnapshot.Expected>
  ) {
    synchronized(roles) {
      require(id.isNotBlank() && receipt.role == role &&
        roles.values.none { it == role } &&
        !documents.containsKey(id) && !paths.containsKey(id) &&
        !receipts.containsKey(id)) { "L1_NATIVE_SESSION_ADMISSION_HOLD" }
      try {
        documents[id] = document
        paths[id] = "LAB_OWNER_VERIFIED_" + role.name
        receipts[id] = receipt
        roles[id] = role
      } catch (failure: Throwable) {
        roles.remove(id)
        receipts.remove(id)
        paths.remove(id)
        documents.remove(id)
        throw failure
      }
    }
  }
}
