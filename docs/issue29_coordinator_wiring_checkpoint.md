# Issue #29 — Coordinator Wiring Checkpoint

Authority baseline: `8bea399bcf269ecdf1c63f9b8f958342cda97d7b` (Flutter Android CI #623 SUCCESS).

## Authorized production mutation

The next code slice is deliberately limited to the existing `ProductRecognitionCoordinator` physical-attempt seam.

1. Import `product_recognition_attempt_dispatch.dart` and `product_recognition_review_result.dart` in `gemini_product_recognition_coordinator.dart`.
2. Add nullable `ProductRecognitionReviewResult? reviewResult` to `ProductRecognitionExecution`; include it additively in safe summary only when present.
3. Replace only the existing `await client.recognize(...)` physical-attempt call with `dispatchProductRecognitionAttempt(...)`.
4. Preserve the returned legacy candidate as `attemptResult.candidate`; propagate `attemptResult.reviewResult` to the successful execution.
5. Extend `_execution(...)` with nullable review evidence and pass it through without changing retry, key routing, model routing, request counting, session semantics, or failure handling.
6. Keep `requiresUserReview` and `canCreateFormalRecord == false` unchanged.

## Required focused regression before UI migration

- Review-capable client: exactly one `recognizeForReview()` request and zero legacy `recognize()` requests per physical attempt.
- Legacy-only client: exactly one legacy `recognize()` request per physical attempt.
- Coordinator success keeps legacy candidate parity and exposes nullable review evidence additively.
- Retry/key/model/session behavior remains byte-for-byte semantically equivalent outside the single dispatch seam.
- `ProductCapturePage` must not call `GeminiProductRecognitionReviewPort` directly.
- No recognition proposal can create a formal transaction, merchant/category binding, or master-data write.

## Frozen governance

`invoice literal != AI interpretation != MerchantBrand != official legal name/branch`.
Registry remains optional/local-first. Normal invoice review has no per-invoice GCIS network dependency. `GCIS_RELEASE_DEPENDENCY=false`.
Formal accounting remains reviewed input → `TransactionEntrySeed` → editable draft → explicit Save → formal transaction.

Merge Authority remains HOLD until successor owner Android real-device validation PASS.
