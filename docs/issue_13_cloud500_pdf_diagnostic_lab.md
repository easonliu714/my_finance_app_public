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


## v4 owner-driven platform renderer experiment

Owner v3 evidence is now CLOSED for third-party pdfiumandroid: the isolated
`:pdfium_open_probe` process reported Android ApplicationExitInfo
`reason=5`, `description=crash`, after two successful heartbeats inside
`PdfiumCore.newDocument()`. Direct Gate 4A reproduced the same process death
when the call was made in the Lab UI process.

v4 therefore prevents the owner from re-running the known crashing third-party
path and adds an isolated Android platform
`android.graphics.pdf.PdfRenderer` probe. On API 35+ it uses
`PdfRenderer.Page.getTextContents()` to extract visible text and perform the
same sorted-PDF binary search for an owner-entered invoice number.

The top authority card reads the installed APK versionName/versionCode/package
at runtime via package_info_plus. Exact branch/head/backend are injected by CI
through dart-define. The Lab applicationId and fixed diagnostic signer remain
unchanged, so v4 must overwrite-install on v3 and preserve the 135 MB PDF and
persistent logs.

Critical native log checkpoints use append + flush + fsync before returning,
maximizing survival of the last BEGIN/heartbeat record if a native process
terminates.


## L0 read-only source crosswalk (evidence only)

A Lab-only Python tool and five focused positive/negative tests compare the
current production PR45 ref with this Lab's exact source commit. The JSON
records version, PDFium/PDFBox versions, SDK, isolated Android process names,
source-file SHA-256, independent diagnostic applicationId and public signer
fingerprint. A moving PR45 ref during fetch is rejected. The existing Lab
diagnostic APK artifact carries the crosswalk JSON only after build gates pass.

L0_CROSSWALK_CAPTURED is NOT L0 runtime PASS. Lab 4.20.18+476 and PR45
4.20.37+495 use different PDF engines/dependencies and IPC routes.
Production generated-host applicationId and effective signer are explicitly
unverified; official PDF and Android runtime are not revalidated. Production
integration, C13/C17/C18, signed upgrade and Owner device all remain HOLD.
No financial data, release signing secrets, production code or main branch
are modified. The PR45 canonical CURRENT documents require reconciliation
in a subsequent PR45-only Writer round; this round writes Lab only.


## L1 offline official PDF evidence auditor — partial CODE+TEST, not L1 PASS

The Lab-only `tools/issue13_lab_l1_official_pdf_audit.py` is a read-only
fail-closed audit of **one exact official PDF** (115-07-08, cloud-500,
135200798 bytes, SHA256
`f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571`)
and a future Android API35 `PdfRenderer` full-page text JSONL export.
It streams the PDF in 1 MiB chunks; it never uploads or writes the source.
For each JSONL line the exact schema is:
`{"page":1,"page_count":N,"pdf_sha256":"<exact official digest>","engine":"android.graphics.pdf.PdfRenderer","period":"115-07-08","tier":"cloud-500","text":"<raw extracted page text>"}`.
Every page 1..N must be present in order, with identical count and scope,
canonical ASCII two-letter/eight-digit tokens, no Unicode compatibility
ambiguity, no duplicate tokens and monotonic page ranges. A mismatch, empty
page, malformed JSON, duplicate JSON key, missing page, or source hash drift
is HOLD. **Page text provenance is not independently attested by JSONL
alone**: even a structural audit PASS leaves extraction completeness,
official publication period/tier provenance, global NOT_WIN, production
integration, C13/C17/C18 and Owner device HOLD.

Offline use after an independently authorized local full-page export:
`python3 tools/issue13_lab_l1_official_pdf_audit.py --official-pdf <local-official.pdf> --pages-jsonl <local-pages.jsonl> --output <local-audit.json>`.
A nonzero exit 49 is a HOLD, not a negative prize result. No official PDF
or native full-page JSONL is available in public CI, so the workflow runs
**12 synthetic positive/negative contract tests only**; this must never be
reported as official L1 source/runtime PASS. The native API35 full-page
bounded export and true 77k/87k official-source completeness remain the next
separate implementation/evidence gates. Do not send real financial data.


## L1 bounded native page-batch export — CODE+TEST, runtime HOLD

The existing isolated `:platform_pdf_probe` API35 service now supports a
Lab-only `LAB_L1_EXPORT:<first>` request. It verifies the exact 135200798-byte
PDF and SHA256 with 1 MiB streaming buffers, then extracts **at most four
consecutive pages** using Android PdfRenderer. Per-page text is limited to
250000 characters / 1 MB JSONL, and each batch to 4 MB. The output is
flushed, fsynced and atomically renamed; incomplete `.part` files are
deleted. The Lab UI persists a next-page cursor only after native completion
and offers sharing the last partial JSONL. Eight new negative/positive batch
contract tests run in Lab CI; the APK build compiles the native service.


The batch is not complete-PDF evidence. Native PdfRenderer may allocate
internally before the post-extraction limit, so an isolated process crash is
still possible. No public CI has the exact official PDF or Android API35
full-page runtime export. A missing batch, crash, token ambiguity, order drift,
or incomplete coverage keeps official L1, global NOT_WIN, production
integration, C13/C17/C18 and Owner UAT on HOLD. PR45 and main are untouched.


## L1 multi-batch chain audit — fail-closed structural convergence

The existing API35 native export produces at most four pages per JSONL batch.
A new **Lab-only** streaming chain auditor accepts a separate directory of
unmodified native `l1-pages-START-REQUEST.jsonl` files and the exact official
PDF. It verifies PDF bytes/SHA before page processing, rejects missing or
overlapping batches, inconsistent page counts, incomplete nonterminal batches,
malformed/oversized JSONL, duplicate keys, untrusted entries, Unicode token
ambiguity, within-page inversions, cross-page inversions and duplicate tokens.
Each batch remains capped at 4 MB / four pages, each line at 1 MB; no full PDF
or page-text corpus is loaded into memory. Synthetic tests exercise the chain.

```bash
python3 tools/issue13_lab_l1_batch_chain_audit.py \
  --official-pdf /path/to/verified-official.pdf \
  --batch-dir /path/to/native-jsonl-only-directory \
  --output /path/outside-batch-directory/l1-chain-report.json
```

**Scope:** CI synthetic chain tests are not an official-source or Android
runtime PASS. Even a complete native JSONL chain is only structural evidence:
renderer extraction completeness and publication period/tier remain
UNATTESTED, global NOT_WIN and production integration remain HOLD. This
change does not request finance records, run the 135 MB PDF in CI, alter
production PR45, or authorize a signed release.


## L1 native cursor recovery and JSONL structural preflight (synthetic only)

The Android Lab UI now validates each completed app-private JSONL batch
before moving its durable cursor: exact official SHA metadata, period/tier,
engine, sequential pages, complete four-page-or-terminal coverage, stable
page count, bounded bytes and text, and no symlink/path escape. A native
batch finalized before UI crash is recovered once rather than re-exported.
Duplicate starts, partial output and metadata drift HOLD. Cursor updates
use a flushed same-directory temporary file and atomic rename.

Existing Lab CI runs new Flutter regressions. This is LAB_CODE_TEST, not
actual official PDF page extraction or renderer completeness evidence.
L1 official/L2–L4/global NOT_WIN/production release/Owner UAT remain HOLD.
