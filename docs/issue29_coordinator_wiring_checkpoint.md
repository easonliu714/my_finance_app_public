# Issue #29 — Coordinator Wiring Checkpoint

Authority baseline: `ad54ba9cb1ea5dbf60e970083f67aa612f4a3c55` (Flutter Android CI #624 / run `35160148637` SUCCESS; required job `Analyze, Test, Build APK` SUCCESS, including Analyze Dart code, full tests, and debug APK build).

## Exact production seam re-read

Fresh exact-head source read confirms the coordinator still has one physical recognition call inside the existing retry/key/model loop:

`final candidate = await client.recognize(...)`

The success path immediately records the attempt/routing event and returns `_execution(...)`. Retry, key routing, model routing, request counting, and session evidence are outside that call. Therefore the authorized mutation remains a narrow dispatch replacement; no coordinator rewrite is authorized.

## Authorized production mutation

1. Import `product_recognition_attempt_dispatch.dart` and `product_recognition_review_result.dart` in `gemini_product_recognition_coordinator.dart`.
2. Add nullable `ProductRecognitionReviewResult? reviewResult` to `ProductRecognitionExecution`; include it additively in safe summary only when present.
3. Replace only the existing `await client.recognize(...)` physical-attempt call with `dispatchProductRecognitionAttempt(...)`.
4. Preserve the returned legacy candidate as `attemptResult.candidate`; propagate `attemptResult.reviewResult` to the successful execution.
5. Extend `_execution(...)` with nullable review evidence and pass it through without changing retry, key routing, model routing, request counting, session semantics, or failure handling.
6. Keep `requiresUserReview` and `canCreateFormalRecord == false` unchanged.

## Exact replacement contract

Before:

```dart
final candidate = await client.recognize(
  apiKey: key,
  model: model,
  imageBytes: image.bytes,
  mimeType: image.mimeType,
);
```

After:

```dart
final attemptResult = await dispatchProductRecognitionAttempt(
  client: client,
  apiKey: key,
  model: model,
  imageBytes: image.bytes,
  mimeType: image.mimeType,
);
final candidate = attemptResult.candidate;
```

Only the success `_execution(...)` receives `reviewResult: attemptResult.reviewResult`. Failure paths remain unchanged and therefore cannot synthesize review evidence.

## Required focused regression before UI migration

- Review-capable client: exactly one `recognizeForReview()` request and zero legacy `recognize()` requests per physical attempt.
- Legacy-only client: exactly one legacy `recognize()` request per physical attempt.
- Coordinator success keeps legacy candidate parity and exposes nullable review evidence additively.
- Retry/key/model/session behavior remains semantically equivalent outside the single dispatch seam.
- `ProductCapturePage` must not call `GeminiProductRecognitionReviewPort` directly.
- No recognition proposal can create a formal transaction, merchant/category binding, or master-data write.

## CI authority rule

Any non-empty commit after `ad54ba9cb1ea5dbf60e970083f67aa612f4a3c55` invalidates CI #624 as current authority. The new exact head must independently pass Analyze, full tests, and APK build before the next production slice is accepted.

## Frozen governance

`invoice literal != AI interpretation != MerchantBrand != official legal name/branch`.
Registry remains optional/local-first. Normal invoice review has no per-invoice GCIS network dependency. `GCIS_RELEASE_DEPENDENCY=false`.
Formal accounting remains reviewed input → `TransactionEntrySeed` → editable draft → explicit Save → formal transaction.

Merge Authority remains HOLD until successor owner Android real-device validation PASS.
