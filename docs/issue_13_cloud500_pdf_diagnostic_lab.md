## Lab L1 period/source custody checkpoint — 2026-11-10 20:13+08

- **Exact-head Lab #46** [run 42809573739](https://github.com/easonliu714/my_finance_app_public/actions/runs/42809573739) on `9245984c3017d89e5a8f54155caa90e9391bc1e7` completed SUCCESS: Native Gradle/JVM including six sorted-page guard tests, 41 Flutter focused, Analyze 0, standalone APK, minimum permissions and fixed Lab signer. Artifact 13761788232. This is synthetic/test and build evidence, not official May-June PDF positive-oracle UAT.
- **Source discovery only:** The Ministry of Finance [cloud award publication page](https://invoice.etax.nat.gov.tw/cloudLastNumber.html) links the 115-05-06 sorted **500元** PDF at `https://invoice.etax.nat.gov.tw/pdf/20260506_20260725124620_sorted_AI_D.pdf`. The current execution environment cannot retrieve and independently hash the binary. Exact 115-05-06 bytes/SHA256, ETag and stable two-read pin remain **HOLD**; a reported content length is not a verified pin.
- New Lab-only `LabL1PeriodSourceIdentity` binds period, tier, source SHA, bytes and parser version. The existing 115-07-08 L1 native export explicitly resolves its already pinned identity before renderer preflight, and writes the period/tier from that identity. Selecting 115-05-06 currently throws `L1_PERIOD_SOURCE_UNPINNED`; it **cannot** reuse 115-07-08 source bytes, cursor, JSONL, cache or manifest. Six synthetic JVM positive/negative cases cover the period/tier/SHA fail-closed contract. No May-June UI, download, or official matched=true/matched=false claim is enabled.
- **Next:** Independently obtain official May-June 500元 sorted PDF bytes and SHA256 from the exact URI, confirm two stable reads/metadata and page contract; only then add period-specific isolated storage and positive/negative device oracle UI. Do not publish private Owner numbers or reuse the July-August source pin. Existing 115-07-08 direct full10 binary remains PRIMARY. Formal C500/Global NOT_WIN/Trusted Signed/Owner production remain HOLD.

## CURRENT — 2026-11-08 20:23 Asia/Taipei | Lab #35 focused+Native PASS, Analyze first failure repaired; successor CI PENDING

Exact Lab HEAD `a3ea2ca356e7e6c44475bf0b37ff29146e94154e` [#35](https://github.com/easonliu714/my_finance_app_public/actions/runs/42479633759) completed FAILURE **after** native Kotlin/JVM and all focused Flutter L1 bundle/search tests passed. The first remaining error was `flutter analyze` 10 `prefer_interpolation_to_compose_strings` infos in `lib/issue13_lab_search_result.dart` lines 112, 118, 143–152. This Lab-only CODE+TEST correction changes only string composition in `LabSearchResult.explanation` and `LabSearchResultCard.build` to Dart interpolation, preserving visible matched/nonmatched/HOLD semantics and exact source/period/page/elapsed metadata. Existing five positive/negative widget tests remain; positive test adds explicit source SHA, period/tier and candidate rendering checks. New exact-head Analyze/APK/signer/artifact must still PASS; no older artifact is valid for this head. Owner 36-page bounded PARTIAL PASS and independent 8-page/400-token JSONL audit are unchanged; full 87000 pages/global NOT_WIN, native PSS/RSS/exit, formal ledger, C13/C17/C18 and Trusted 9BA2 Signed remain HOLD. PR45/main/canonical CURRENT unchanged.

## CURRENT — 2026-11-08 20:16 Asia/Taipei | Lab #34 first true Flutter compile failure repaired, successor CI PENDING

Fresh-read Lab HEAD `644a7eccdb6153a3f62accbcf3c4fbacfd6b8416`, PR45 `cc2bb0aefe0965c81489090e63f0dbe070aae89f` OPEN/DRAFT, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`. Lab #32 [42470926168](https://github.com/easonliu714/my_finance_app_public/actions/runs/42470926168) failed at native Gradle dependency HTTP 504, not source. Lab #33 was superseded/cancelled. Lab #34 [42475345617](https://github.com/easonliu714/my_finance_app_public/actions/runs/42475345617) completed FAILURE on exact `644a7ecc`: native Kotlin/JVM passed, search-result widget tests passed, but focused bundle test could not load: `lib/issue13_lab_l1_evidence_bundle.dart:22:18` ambiguous `Sha256` exported by `archive_io` and `cryptography`. Smallest Lab-only CODE+TEST repair explicitly qualifies `cryptography.Sha256` in the streaming `_sha` helper, preserving the archive encoder and all fail-closed guards. Positive ZIP regression independently compares manifest JSONL SHA against hashed original file bytes. Successor exact-head Kotlin/JVM, focused tests, Analyze, APK, stable Lab signer and artifact **PENDING**; parent #31 is not successor authority. Owner bounded 36-page physical PASS and two independently audited JSONLs (8 pages/400 tokens) remain historical partial evidence; missing pages 5–32 independent audit, native PSS/RSS/exit, 87000-page completeness and global NOT_WIN remain HOLD. No production ledger, PR45, main, official PDF or trusted 9BA2 signing change.

# Issue #13 Cloud-500 PDF Diagnostic Lab

## Lab diagnostic engineering checkpoint — 2026-11-10 Asia/Taipei | Exact ten-character sampled-page guard and two-period synthetic contract

The owner approved retaining direct full-ten-character binary PDF search as the primary diagnostic engine, with lazy prefix bounds only as an optional measured accelerator. This SOURCE+TEST patch routes the native sampled-page extractor through `LabL1SortedPageGuard`: an invalid candidate, fewer/more than 50 tokens, duplicate tokens or malformed embedded text produces a typed error/HOLD rather than a silent false nonmatch. Original L1 streaming JSONL, cursor, renderer lifetime and production app are unchanged.

New focused JVM regression fixtures explicitly cover both `115-05-06` and `115-07-08` synthetic page cases for exact positive and negative ten-character matches, cross-period isolation, 49/51-token gaps, duplicates, embedded garbage and invalid input. **These are synthetic cases, not a claim that May–June real official Cloud-500 winners were already tested.** For a genuine `115-05-06` Cloud-500 positive/negative oracle, first independently pin the corresponding official sorted PDF URI, bytes and SHA256 and select the correct period-specific source/cache. A publicly documented million-dollar winner is a different tier and must not be treated as a Cloud-500 positive. User-provided known-winning candidates remain private and may be checked only in the isolated Lab after official source matching. Pending official source proof, Android positive/negative evidence, exact-head CI, full-page completeness, native RSS/PSS and exit, formal `NOT_WIN`, Trusted9BA2 and production integration are HOLD.


## Owner 18:18 native search + diagnostic result UX correction — 2026-11-08

Owner physical Lab #31 (0.4.31+900031, exact cbaad08) produced a 398-line
debug log: 18:18:08–18:18:16 local-pinned official cloud-500 PDF binary search
for CR30912111 sampled 17 pages in 6612 ms, native PID 8016,
status=complete, matched=false, matched_page=0, ACTION_OK, no crash.
This is **only a nonmatch in this specified PDF**; not all 87000 pages
independently extracted, not other tiers, not global NOT_WIN, and no formal
ledger write. External viewer ACTION_OK is dispatch-only; Open Only returned
87000 pages. Original Owner logs/PDF/JSONL are not published in the repository.

Root UX defect: _platformBinarySearch only wrote Debug Log, while _run
overwrote completion with generic “完成”. This Lab-only SOURCE+TEST change
introduces a visible result card with mode=DIAGNOSTIC_ONLY, period,
locally pinned source SHA, candidate, sampled pages/page count and elapsed.
Positive match explicitly says not formal winning/posting; nonmatch explicitly
disclaims other tiers and NOT_WIN. Failure, timeout, invalid candidate,
wrong source/period/tier or malformed native result fail closed to HOLD.
Flutter widget regressions cover matched/nonmatched/invalid/timeout/other
tier. No production ledger, PR45 or signer change.

Lab #32 exact d12888b9 CI 42470926168 failed in Gradle native preflight
before Flutter tests/APK: dependency download kotlin-compiler-embeddable-2.4.0.jar
received upstream HTTP 504 (GitHub JetBrains release), **not** a Kotlin source
compiler diagnostic. New HEAD CI must independently pass native JVM, all
focused tests, Analyze, APK, fixed Lab signer and artifact; parent Lab #31
cannot be used as evidence. Official full-page and global NOT_WIN remain HOLD.


## Owner Android official-source partial checkpoint — 2026-11-08 18:00–18:07 Asia/Taipei

**Evidence authority and limits:** Owner physical Android Lab `0.4.31+900031`,
`com.easonliu.cloud500diag`, SDK37, exact Lab HEAD
`cbaad08aa3709d098951797a841a98b43aa2c912`. Lab #31
[42441386432](https://github.com/easonliu714/my_finance_app_public/actions/runs/42441386432)
was exact-head CI SUCCESS; the Owner runtime evidence is separate and newer.
Dart/Native Debug Log: 292 lines, SHA-256
`fc875c7fbc62a9134e02659579f4e9abc0337f5b1225f79969f1a0be4ec07082`.
Official publication page and sorted PDF returned HTTP 200. Owner Lab recorded
135200798 bytes and local per-batch SHA-256
`f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571`;
the original 135 MB PDF was **not** supplied for independent rehash.

One isolated native PID 8016 produced nine `PLATFORM_RENDERER_OPEN_OK` events
and `L1_SOURCE_PREFLIGHT_PASS`, `LOCAL_VALIDATE_PASS`,
`PLATFORM_PROBE_COMPLETE`, `L1_PARTIAL_BATCH_CAPTURED`.
Owner completed pages 1–4 plus eight four-page batches 5–36:
**36/87000**, `next_page=37`, `cursor_reached_end=false`,
without `ACTION_ERROR` or `FAILED` in the supplied run.

Two actual JSONL files were independently parsed and strictly checked:
- `l1-pages-1-1794132287536630.jsonl`, SHA-256
  `2dcbdfba8c36fa88cc47937c9ffd9e2bec65a7e879c1c88be7d60b8423f5d254`,
  pages 1–4, 200 tokens.
- `l1-pages-33-1794132379505428.jsonl`, SHA-256
  `945ce06f7958301fd768fdff3da5f38d1418b3abd06bc86bd498f8e423e1707c`,
  pages 33–36, 200 tokens.

Both files had 50 tokens/page, no duplicates, ordered tokens, zero duplicate
JSON keys, and matching 87000 page count, period/tier, Android renderer and
source digest. **The seven intermediate JSONL files for pages 5–32 were not
provided for independent audit.** Do not extrapolate those two samples to an
independently verified 36-page chain.

Gate classification:
- `OWNER_DEVICE_LAB_BOUNDED_36_PAGE_POSITIVE=PASS`
- `OFFICIAL_SOURCE_RUNTIME_PIN_MATCH=PASS_BY_LAB_LOG`
- `TWO_JSONL_INDEPENDENT_STRUCTURE=PASS`
- `LAB_L1_OFFICIAL_FULL_PAGE=HOLD`; `GLOBAL_NOT_WIN=HOLD`
- `NATIVE_PSS_RSS_AND_PROCESS_EXIT=UNKNOWN` (nine opens on one PID do not
  establish process exit; JVM heap is not native RSS/PSS)
- Native close-before-terminal remains source/JVM synthetic evidence, not
  physical close-event tracing or injected-close-failure device evidence.
- C13/C17/C18, PR45 formal posting, Trusted 9BA2 Signed, production Owner
  installed/device, and MERGE_READY remain HOLD. No formal finance SQLite,
  NT$700 posting, or accounting data was touched.

## Bounded multi-batch evidence share — Lab SOURCE+TEST candidate, CI pending

A Lab-only explicit share action packages **up to 12 complete four-page
JSONL batches**, the Lab Dart/Native debug logs, and a SHA-256 manifest into
one streaming ZIP. It checks the full retained sequence from page 1 through
the durable cursor (the current 1–36 chain fits), exact native JSONL metadata,
one file per batch start, missing/overlapping/partial files, symlink escape,
a pending native dispatch fence, 48 MB JSONL, 2 MB logs and 64 MiB ZIP
limits. It rehashes source files after ZIP creation and never includes the
135 MB official PDF or any production finance database. One fixed output ZIP
prevents accumulating unlimited share copies. Errors do not advance cursor
or delete native JSONL. The owner must explicitly tap Share; no automatic
upload or background network transfer occurs.

The manifest marks `independent_token_and_source_audit=PENDING`,
`native_pss_rss_and_process_exit=UNKNOWN`,
`official_full_page_evidence=HOLD`, `global_not_win=HOLD` and
`production_authority=HOLD`. The archive contains the Lab logs, which may
include a manually entered invoice candidate; share only through a trusted
destination. It does not attest original PDF bytes, independently audit all
tokens, or instrument native PSS/exit. Focused positive and fail-closed
regressions are wired into the same-head Lab CI, **not yet PASS**.

**NEXT_DoD:** exact-head Flutter focused tests, Analyze, native JVM, Lab APK,
fixed signer and artifact all PASS; then Owner may use the new standalone Lab
version to share one 1–36 evidence bundle. Independent archive/manifest/JSONL
audit and separate native PSS/RSS/process-exit instrumentation precede any
broader page-coverage claim. Do not request thousands of manual batches or
declare full 87000-page/global NOT_WIN authority.

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

## L1 native source custody before PdfRenderer — pre-renderer CODE+TEST

The isolated Android API35 L1 export now validates the app-private official
PDF's canonical path, exact 135200798-byte length and streaming SHA-256
**before** constructing PdfRenderer. Invalid start/request identifiers and
out-of-scope JSONL output paths also fail before renderer construction.
This reduces exposure to unverified PDF input and avoids opening native
renderer state for a source that cannot satisfy the pinned official contract.
It does not eliminate native PdfRenderer OOM or prove a concurrent file cannot
change between verification and renderer open; no global NOT_WIN authority.

Six JVM unit regressions exercise valid bytes/hash, wrong length, wrong SHA,
same-length modification, outside-root path and symlink escape. Lab CI also
enforces pre-renderer call ordering and compiles the plugin via Gradle.
These use tiny synthetic files: they are not the official 135 MB PDF,
not Android API35 full-page runtime extraction and not L1 official PASS.
PR45, production signing, installed Owner data and main are unchanged.


## L1 persistent native in-flight dispatch custody — CODE+TEST, official HOLD

A two-minute Dart timeout does not prove the isolated Android PdfRenderer
process exited. An app restart could previously forget an unresolved native
request and redispatch the same pages, risking concurrent native memory use
and duplicate JSONL. The Lab now creates an exclusive, flushed, app-private
`l1-native-inflight.json` marker immediately before native L1 dispatch,
binding exact first page, numeric request ID and pinned official PDF SHA.
Timeout, crash, malformed/symlinked marker, identity mismatch or unknown
process outcome remain HOLD across restarts. No automatic retry or cleanup.

Only a terminal native success plus strict verified JSONL can release the
marker, before cursor save. A crash after release can use the existing
finalized-batch recovery. Stranded markers require independent process-exit
and evidence review before manual clearance. Five synthetic Flutter tests
cover exclusive admission, restart HOLD, mismatch, torn/symlinked markers
and terminal release. No actual 135200798-byte official PDF Android run,
77k+87k completeness, Unicode/period/tier or global NOT_WIN is attested.
L1 official/L2-L4/C13/C17/C18/Owner/Trusted Signed remain HOLD.


## L1 renderer-close-before-terminal custody — native CODE+TEST, official HOLD

Native L1 previously published `status=complete` after JSONL fsync/rename
but **before** closing Android `PdfRenderer` in `finally`. The Dart
dispatch fence could then be cleared while the prior native renderer still
held resources. The Lab now closes the renderer and descriptor before
publishing terminal success. If close throws, the native failure path runs
and the durable Dart fence remains unresolved; no new batch is dispatched.
The heartbeat is stopped before the final complete snapshot.

Two native JVM regressions verify close-before-success ordering and
fail-closed behavior when resource closure throws. Existing cursor,
bounded-run, native preflight, and signer gates remain required.
This does not prove isolated-process exit, official 135200798-byte PDF
Android full-page extraction, renderer text completeness, global NOT_WIN,
Owner installation, or production authorization. L1 official/L2-L4 HOLD.

## L1 isolated native PSS/RSS sampling — SOURCE+TEST, device evidence HOLD

The isolated Android platform PDF worker now samples `Debug.MemoryInfo.totalPss`
and `/proc/self/status VmRSS` in kB alongside bounded native log events.
Unavailable, malformed, zero or overflowed readings are recorded as UNKNOWN,
not a fabricated zero or PASS. A `L1_RENDERER_CLOSED_BEFORE_TERMINAL` event
is logged after resource closure but before terminal success publication.
Three pure JVM regressions cover valid RSS, malformed/missing/overflow RSS,
and mandatory `native_process_exit=UNKNOWN` despite observed PSS/RSS.

This is diagnostic instrumentation only. The measurements are per-process
snapshots, not peak native memory, not `ApplicationExitInfo` process-exit
proof, and not proof of full 87,000-page extraction or global NOT_WIN.
Exact-head Lab CI, Android Owner memory samples and independently confirmed
process exit remain pending. Production PR45, signing authority, Owner data,
formal app version, and canonical project governance are unchanged.
