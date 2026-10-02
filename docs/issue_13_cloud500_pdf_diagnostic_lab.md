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
