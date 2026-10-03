# Issue #13 Cloud-500 PDF Diagnostic Lab

Standalone Android diagnostic branch for the 115-07-08 cloud-exclusive NT$500
official sorted PDF. This lab is intentionally separated from production PR #45.

## Exact source contract

- period: `115-07-08`
- expected bytes: `135200798`
- expected SHA-256:
  `f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571`
- source URL is resolved at runtime from the official MOF
  `cloudNowNumber.html` publication surface; the lab rejects any non-official
  or non-sorted cloud-500 artifact.

## Test modes

1. Download/validate the exact official PDF into the lab app's own Application
   Support directory. Subsequent runs reuse the validated local copy.
2. Dispatch the same file to an installed Android PDF viewer through FileProvider.
3. Run only native PDFium `newDocument -> pageCount`.
4. Enter any invoice number and run:
   - direct in-process PDFium binary search with page-by-page debug evidence;
   - the production isolated-worker candidate path for comparison.

Both Dart and native code write persistent timestamped diagnostics. Native
evidence includes PID, thread, JVM heap, file bytes, PDFium open begin/end,
page open, text extraction, elapsed time, and stack traces on caught failures.
The Dart log records download SHA/bytes, binary-search bounds/decisions,
page token first/last values, result pages, worker stages and progress.

This branch is a diagnostic lab only. It is not release authority and must not
be merged into production without a separate reviewed successor decision.


## v3 isolated open probe

Owner v2 evidence proved that the exact 135,200,798-byte PDF opens in the
Android system viewer, while pdfiumandroid 1.0.35 terminates the app process
inside `PdfiumCore.newDocument()` before any Java/Kotlin exception is returned.

v3 therefore:
- upgrades only the Lab to stable `io.legere:pdfiumandroid:2.0.1`;
- runs Gate 3 in `:pdfium_open_probe`, never in the Lab UI process;
- emits a 2-second heartbeat while native document-open is in progress;
- if heartbeat stops, the UI queries Android `ApplicationExitInfo` and records
  process running state, exit reason/status, importance, PSS/RSS, timestamp and
  description when the platform exposes them.

Production PR #45 remains frozen; this dependency change is diagnostic-only.


## Stable overwrite-install signing

Beginning with Lab v3, the standalone package uses a fixed diagnostic-only
signing certificate and monotonically increasing Lab versionCode. This is
deliberately separate from production signing authority.

Android requires both the same applicationId and signer for an in-place update.
The earlier v2 APK used an ephemeral CI debug key, so **one final uninstall is
required when moving from v2 to the first stable-signed Lab build**. After that
transition, future Lab APKs can be installed over the existing Lab and preserve
the downloaded official PDF, cache and debug logs.

Stable Lab signer SHA-256:
`51c7fc93ef3d2a04bcd993e6e716b37949efdb74be9af7f48689cfc7ff5c3c53`
