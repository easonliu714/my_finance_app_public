package me.movenext.flutter_pdf_text

import java.io.File

/**
 * PDFium source authority: the verified SHA and the parser descriptor must
 * refer to the same unlinked snapshot inode. A second open of the mutable
 * caller-provided PDF pathname is never authorized.
 *
 * This bounds pathname-swap TOCTOU, NOT arbitrary same-UID writable-FD
 * mutation after return or full independent-process trust.
 */
internal object PlatformPdfiumSourceAuthority {
  fun capture(
    source: File,
    privateDirectory: File,
    expectedBytes: Long,
    expectedSha256: String,
    onProgress: (Long) -> Unit = {}
  ): PlatformSourceSnapshotCustody.VerifiedSource =
    PlatformSourceSnapshotCustody.capture(
      source, privateDirectory, expectedBytes, expectedSha256, onProgress
    )
}
