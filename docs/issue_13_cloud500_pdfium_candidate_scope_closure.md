# Issue #13 — Cloud-500 PDFium candidate-scope closure

Authority scope: PR #45 branch `issue-13-invoice-award-official-data`; Draft / OPEN / Merge HOLD.

## Successor invariant

The >120 MiB cloud-500 path is the native PDFium random-access exact-candidate worker. It must never return to PDFBox whole-document materialization.

Before release rotation, the worker boundary must fail closed unless the candidate universe is all of the following:

- non-empty;
- normalized to exact `^[A-Z]{2}[0-9]{8}$` invoice numbers;
- duplicate-free after normalization;
- sorted deterministically before hashing/search;
- SHA-256 bound to the caller-provided candidate-universe authority.

An empty candidate array is not valid authority even if its SHA-256 is internally self-consistent. The worker must reject it before source SHA verification or PDFium document open. This prevents a vacuous `complete` result from being mistaken for candidate verification.

## Promotion evidence

A successful worker result must remain bound to the exact official PDF source SHA-256 and byte length, the exact candidate-universe SHA-256, and page evidence for every positive match. Running/failed states are diagnostic only and must never promote cloud-500 authority.

## Next smallest-safe production mutation

Tighten `PdfiumCandidateWorkerService.runLookup` candidate-scope validation from size-parity alone to `candidates.isEmpty() || candidates.size != raw.length()` (or an equivalent explicit non-empty fail-closed guard), retaining `PDFIUM_WORKER_CANDIDATE_SCOPE_INVALID`. Add a regression that proves the empty universe is rejected before `PDFIUM_SOURCE_SHA256` / `PDFIUM_OPEN_BEGIN`, while valid exact candidates retain the bounded PDFium path.

This mutation changes no winner semantics, amounts, general-award authority, LKG policy, accounting/import/report/manual-review behavior, or network source policy.
