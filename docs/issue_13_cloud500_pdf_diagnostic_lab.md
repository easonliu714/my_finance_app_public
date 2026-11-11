## Lab 115-05-06 staged dual-PDF point-of-use custody — 2026-11-12 04:xx +08 | SOURCE+TEST, exact-head CI PENDING

**Confirmed defect:** capture-time full-byte SHA and fsync do not prove the staged PDF remained unchanged when a later dual-role diagnostic consumer opens it. `requireDistinctPair()` checked candidate metadata only, so post-capture same-length tampering, a swapped staged file or deletion was not rejected at that comparison boundary. **New Lab-only source:** `requireDistinctStagedPair()` first requires distinct sorted/draw-order roles and digests, then independently rehashes each complete on-disk candidate with 64 KiB memory, validates exact period/tier/role/SHA filename, canonical path, candidate authority, SHA format and byte count. Two focused Kotlin/JVM tests cover a valid distinct pair, same-length post-capture tampering, role/file swap and missing file, without altering Owner records. A standalone Kotlin syntax/positive-negative prototype passed; only exact-head GitHub native Gradle/JVM/Flutter/APK/permission/Lab-signer CI can validate this integrated commit.

**Safety/authority:** This is a diagnostic point-of-use readback, not an atomic immutable consumer handle, independent official HTTPS attestation, official source SHA pin, actual 500元 WIN/NOT_WIN, or formal release. `L1_PERIOD_SOURCE_UNPINNED`, 115-07-08 LKG/cursor73, private tickets, Scheme C fail-closed, C13/C17/C18, V25, full87k/global NOTWIN, Trusted Signed, Owner UAT and MERGE HOLD remain unchanged. Official sorted and draw-order 115-05-06 full bytes remain unavailable in this runtime; do not repeat the DNS-blocked bulk download. Next measurable DoD: exact-head Lab CI plus separately acquired complete official bytes/independent SHA for each role and verified real full10 cross-PDF positive; independent full-coverage negative remains HOLD.

## Lab May-June full-byte HTTPS staging custody — 2026-11-11 22:15+08 | SOURCE+TEST; exact-head CI PENDING

**Root cause:** Existing bounded official GET computed a SHA-256 but discarded the PDF bytes, preventing independent sorted/draw-order full10 inspection. **New Lab-only source:** `fetchOfficialToStaging()` retains the full official HTTPS response in an app-private temporary file with the existing 200 MB/30-minute limits; `auditResponseToStaging()` fsyncs, independently re-reads every byte/SHA and renames to period/tier/role/SHA without overwriting existing candidates. Failure deletes partial files. Four focused JVM tests cover distinct-role byte readback, incomplete/malformed cleanup, duplicate refusal and invalid directory. This is a staged diagnostic candidate only, NOT an independently authenticated official SHA pin or WIN/NOT_WIN oracle; May-June `L1_PERIOD_SOURCE_UNPINNED` remains HOLD.

**NEXT:** exact-head Native Gradle JVM including 16 focused provenance tests, Flutter 41+, Analyze0, standalone Lab APK, permission/signer/artifact. On a network-capable host acquire both official distinct full PDFs, verify each independent source SHA, then crosscheck a verified draw-order Cloud500 full10 in sorted PDF; independent full-coverage negative remains HOLD. Preserve Owner 72-page/cursor73 July-August LKG, private tickets, production Scheme C and signer.

## Lab May-June HTTPS bounded elapsed-time acquisition — 2026-11-11 21:15+08 | SOURCE+TEST; exact-head CI PENDING

**Fresh authority:** main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, PR45 OPEN/DRAFT `a65053a8acf74c794f2e457ad39e535e58884e32` with #1453 exact-head 3/3 SUCCESS (Analyze0, 2432 PASS/1 SKIP, API35 nine, ephemeral Release-AOT five; NOT Trusted Signed); Lab parent `70ab0c217287a17c4b3006ed6edaf05e7fad514c` #51 run 43019907631 SUCCESS, 41 Flutter tests, native Gradle, separate diagnostic APK and Lab signer. No official 115-05-06 PDF raw bytes or independently pinned SHA; `L1_PERIOD_SOURCE_UNPINNED` remains HOLD.

**Root cause and executable change:** The existing 200 MB stream byte cap, 32 consecutive empty-read guard and 30-second *per-socket-read* timeout do not limit aggregate transfer time: an adversarial or degraded HTTPS server can drip a nonzero chunk before each read timeout for arbitrarily long. `LabL1MayJuneOfficialStreamProvenance.auditResponse()` now uses a monotonic elapsed 30-minute deadline checked both before and after each blocking read; `fetchOfficial()` inherits the default monotonic clock without widening trust. Two focused deterministic JVM tests inject a fake monotonic clock to prove slow-trickle HOLD and timely complete-stream candidate behavior. No source URL, period/tier, SHA pin, owner ledger, July-August cursor/LKG, production release or trusted signer changed. Synthetic stream PASS is not independent official PDF acquisition or actual WIN/NOT_WIN.

**NEXT measurable DoD:** exact-head Lab native Gradle JVM including 12 focused provenance cases, Flutter 41+, Analyze0, separate APK, merged permission and Lab signer, artifact. If PASS, next official-source Gate needs both complete distinct HTTPS bodies with independent SHA256 and a draw-order positive full10 crosscheck; separately attested complete negative remains HOLD. Do not repeat failed DNS bulk downloads.

## Lab May-June official dual-PDF bounded HTTPS stream provenance — 2026-11-11 evening +08 | SOURCE+TEST; successor exact-head CI PENDING

**Scope / first real blocker:** Lab HEAD before this change `b9c18d34424f54dfa952875a139f9a5b1a2ce427`; PR45 B2.27 exact `a65053a8acf74c794f2e457ad39e535e58884e32` Flutter Android #1453 run 43010966392 independently verified 3/3 SUCCESS (Analyze0, 2432 PASS/1 SKIP, API35 9 JUnit, ephemeral Release-AOT five runtime markers; NOT Trusted9BA2 Signed). Two distinct 115-05-06 official Cloud-500 PDF GETs cannot be completed from this execution environment: DNS lookup of `invoice.etax.nat.gov.tw` failed (`NameResolutionError`), and the web fetch interface reports both PDF URLs inaccessible. No original PDF bytes, page counts, official SHA-256 pins, positive draw-order token or independent full-coverage negative were obtained. Do not repeat a futile bulk fetch or promote HTTP Content-Length to a byte pin.

**New Lab-only executable SOURCE+TEST:** `LabL1MayJuneOfficialStreamProvenance` introduces separate sorted/draw-order exact official HTTPS URLs, TLS platform validation, redirect rejection, identity response encoding, explicit HTTP 200 and PDF media type, 10-second connect/30-second socket timeouts, 200 MB per-PDF byte cap, 64 KiB bounded streaming SHA-256, 4 KiB PDF terminal trailer check, optional declared length agreement, response ETag/Last-Modified as *metadata only*, and explicit distinct-role/different-SHA pair verification. A stream failure, truncated body, malformed PDF envelope, role/URI swap, 302/403/429, gzip, oversized body or reused 115-07-08 SHA fails closed. The resulting evidence is `HTTPS_STREAM_CANDIDATE_NOT_OFFICIAL_PIN`, never an official publication pin, actual full-page PDF parsing or WIN/NOT_WIN authority. The stream core can be exercised without network; ten focused Kotlin/JVM synthetic positive/negative tests passed locally with Kotlin/JUnit-signature stubs. GitHub native Gradle, Flutter Analyze, APK/signer/permission evidence remain **PENDING for the new exact HEAD**, and local stubs do not substitute for them.

**Next independent DoD:** From an environment with working official HTTPS, stream **both** distinct GET bodies in full, record separate role/URI/period/tier/actual bytes/SHA-256/parserVersion and HTTP provenance, then independently cross-check the two official files before proposing May-June pin promotion. Preserve `LabL1PeriodSourceIdentity.requirePinned("115-05-06") == L1_PERIOD_SOURCE_UNPINNED` until independent source authority is established. The real positive requires a verified full 10-character Cloud-500 draw-order token located in the sorted PDF via direct full10 binary; the real negative needs separately attested full coverage. Do not touch July-August LKG/cursor73, Owner's 72-page/3600-number private evidence, Owner ledger, trusted signer, production Scheme C, or release. No additional Writer/PR.

## Lab May-June dual-official-PDF oracle contract — 2026-11-11 00:15+08 | SOURCE+TEST candidate, successor exact-head CI PENDING

**Fresh source/CI:** Lab #49 [run 42832888739](https://github.com/easonliu714/my_finance_app_public/actions/runs/42832888739) exact `2dc117c56a5fe72f21eba7e0a0e0c628c34a2d22` SUCCESS (native Gradle/JVM, 41 focused Flutter, Analyze0, standalone APK, least-privilege merged manifest, independent Lab signer). Formal PR45 #1442 [run 42806593204](https://github.com/easonliu714/my_finance_app_public/actions/runs/42806593204) exact `100050dd72dfc9e3d4dedb39213a3b80d6814c06` 3/3 SUCCESS but remains OPEN/DRAFT, not Trusted9BA2 Signed or Owner production. Owner Lab #39 two-window 72-page/18-batch/3,600-number private ZIP audit remains limited PASS; #36 share failure historical.

**New bounded SOURCE+TEST:** Add pure Lab-only `LabL1MayJuneDualPdfOracle` and ten synthetic Kotlin/JVM positive/negative/failure-injection regressions. Require distinct official `115-05-06` `cloud-500` source roles/URIs/bytes/SHA/parserVersion: draw-order `https://invoice.etax.nat.gov.tw/pdf/20260506_20260725124620_AI_D.pdf` is the independent positive token/page oracle, sorted `https://invoice.etax.nat.gov.tw/pdf/20260506_20260725124620_sorted_AI_D.pdf` is the direct full-10 binary query source. Verify both actual byte pins via injected independent verifier (default **reject**); positive requires the identical ten-character token in both valid pages. Negative requires a separate full-coverage, all-tokens-valid draw-order absence attestation and independent verifier (default **reject**); a single binary miss or partial pages is not an absence proof. Mismatched source, SHA, period, tier, parser, invalid/duplicate/unsorted page tokens, wrong returned page/token, missing proof and verifier exception all HOLD. Even passing synthetic contract returns `LAB_DIAGNOSTIC_ONLY`, never formal WIN/NOT_WIN.

**Independent official provenance HOLD:** The official [May-June Cloud-500 publication page](https://invoice.etax.nat.gov.tw/cloudLastNumber.html) lists both PDFs, but reported HTTP Content-Length values (~119,769,589 sorted / ~146,461,156 draw-order) are **unverified candidates**, not downloaded bytes, SHA256, PDF page-count, complete draw-order proof or real matched=true/false evidence. Both actual PDF SHA256 pins remain UNKNOWN, and `LabL1PeriodSourceIdentity.requirePinned("115-05-06")` MUST continue to throw `L1_PERIOD_SOURCE_UNPINNED`. No May-June Android oracle is enabled, no Owner private ticket is requested or published. The May-June 2026-11-05 prize-claim deadline has passed; this is historical algorithm validation only.

**No runtime integration:** This contract has no IO/network/SQLite/cursor/JSONL/LKG/official 07-08 source/production dependency. The July-August direct full-10 PDF binary remains PRIMARY; lazy prefix bounds remain diagnostic. Local kotlinc/JUnit-signature stub tests **10/10 PASS**; exact successor GitHub Gradle Native JVM/Flutter 41+/Analyze/APK/signer/permission artifact is **PENDING** and cannot inherit #49 PASS. Next: verify successor exact-head CI and first raw failure; independently obtain and hash both official PDFs before any real May-June positive/negative Android oracle. C500 Scheme C Release fail-closed, global NOT_WIN, native PSS/RSS/exit, Trusted Signed, Owner ledger and MERGE remain HOLD.

## Lab local-copy PDF envelope hardening — 2026-11-10 22:16+08 | SOURCE+TEST, exact-head CI PENDING

The existing two-copy candidate audit accepted two identical header-only files as a local PDF candidate because it checked only `%PDF-`. Add a bounded 4 KiB trailer ring buffer and require terminal `%%EOF` with ASCII whitespace only. Matching copies without the terminal marker, with non-whitespace after it, or with a marker only outside the last 4 KiB now fail closed as `L1_LOCAL_COPY_PDF_TRAILER_MISSING`. Synthetic tests cover both negative cases and a stream spanning the 4 KiB trailer capacity. No real PDF, private ticket, network, formal database, parser, cursor, manifest, or signer is touched. This is only an additional structural envelope check: it does not prove an official May-June source pin or authorize `requirePinned("115-05-06")`. Parent Lab #48 exact `b3a955a49bf7cb6f760551bcd07d495f4a075006` SUCCESS; successor must independently pass Native JVM, 41 focused Flutter, Analyze, APK, permissions and stable Lab signer.

## Lab local-copy source proof candidate — 2026-11-10 21:16+08 | SOURCE+TEST, not official pin

The official publication page links the **115-05-06 sorted Cloud-500** PDF at `https://invoice.etax.nat.gov.tw/pdf/20260506_20260725124620_sorted_AI_D.pdf`. The execution environment cannot independently fetch/hash its 119,769,589-byte HTTP-reported payload, so the **actual file SHA256 and stable independent HTTPS provenance remain HOLD**. HTTP-reported length is not a trusted pin.

New Lab-only `LabL1MayJuneLocalCopyAudit.auditLocalCopies` is a bounded **read-only local candidate proof**: two distinct app-private files, canonical path and same-file/hardlink rejection, exact period/tier/URI, streamed SHA256 and bytes, PDF magic, 200MB cap, and explicit refusal to reuse the July-August source SHA. It returns `LOCAL_COPIES_ONLY_NOT_OFFICIAL_PIN`, never enables `requirePinned("115-05-06")`, never downloads or reads Owner ledger, and never writes cursor/JSONL/LKG. Eight synthetic JVM regressions include positive local-copy agreement, wrong period/tier/URI, duplicate/hardlink, same-length corruption, truncation/bad header, path/symlink escape, byte budget and no-write contract. Local kotlinc with JUnit signature stubs: 8/8 PASS; exact-head GitHub Gradle/Flutter/Analyze/APK/Signer CI is required separately.

NEXT: obtain two independently sourced official May-June PDF copies/metadata, compute actual SHA twice, verify provenance and full-page layout before approving a May-June pin. Only after that add isolated period selection and private Owner matched=true/matched=false Android oracle. **No official May-June winning or nonwinning verdict yet.**

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
