# P4.19.2 Product Photo Transaction Capture

Status: REQUIREMENTS_FROZEN / IMPLEMENTATION_START
Base: P4.19.1+437 frozen exact head `3508be2158ffbeb0d19d9272fde8825492efd4e8`
Branch: `p4-19-2-product-photo-transaction-capture`

## 1. Goal

Turn the existing Home `拍照` / `拍商品` flow into a complete review-first product-photo bookkeeping vertical slice:

`camera/gallery -> local staging -> Gemini product candidate -> user review -> prefilled transaction entry -> explicit user save`

This phase does **not** allow AI or image capture to create a formal transaction directly.

## 2. Existing authority to reuse

- `ProductCapturePage` already exposes camera/gallery capture and local staged-image discard.
- `ImageCaptureStagingItem` already distinguishes `DailyCaptureIntent.product`, remains local-only, and forbids automatic transaction creation.
- `ProductionImageCaptureCoordinator` already provides duplicate/replay protection and staged-image lifecycle.
- P4.19.1 provides the reusable Gemini Key pool, provider model catalog, bounded Key/model fallback, Frozen-image authority, and recognition progress UI.
- `TransactionEntryPage` remains the only formal user-facing transaction editor/save boundary.

## 3. P4.19.2 candidate contract

A product recognition result is a **candidate**, never a transaction.

Minimum candidate fields:

- `productName`: optional string
- `quantity`: optional positive number
- `unitPrice`: optional non-negative number
- `totalAmount`: optional non-negative number
- `categorySuggestion`: optional string
- `merchantName`: optional string
- `recognizedText`: optional compact evidence string
- per-field confidence where available
- warnings / review reasons

Rules:

1. Missing/uncertain fields remain empty; Gemini must not invent exact values to make the form complete.
2. `totalAmount` is not derived from `quantity * unitPrice` unless both operands are explicit trusted candidate values. A derived amount must be labelled derived, not observed.
3. Category and merchant are suggestions only.
4. Product name may represent one visible product or a compact summary when multiple products are visible; P4.19.2 does not silently create multiple formal transaction rows.
5. Candidate always requires user review.

## 4. AI invocation contract

For product recognition there is no deterministic Local OCR authority equivalent to invoice Local-first.

Therefore the first vertical slice uses an **explicit user action** `AI 辨識商品` after an image has been staged. That action constitutes consent for one logical Gemini product-recognition invocation.

The invocation reuses P4.19.1 resilience:

- same flat API Key pool;
- same provider model catalog;
- same Flash-model fallback;
- same bounded retry policy;
- same active-model + elapsed-time indicator;
- same raw-Key redaction;
- exact staged image bytes remain the request authority across retries.

No background/implicit product-image upload is introduced in P4.19.2.

## 5. Review UI contract

After successful recognition the product page shows:

- image source / staged filename;
- AI running status while pending;
- candidate product name;
- quantity;
- unit price;
- total amount;
- category suggestion;
- merchant suggestion;
- warnings;
- `重新 AI 辨識` action;
- `帶入新增記帳` action;
- `丟棄照片` action.

`帶入新增記帳` must only open `TransactionEntryPage` with a seed. It must not call `TransactionRepository` or any formal-write service.

## 6. Transaction handoff contract

P4.19.2 extends `TransactionEntrySeed` so a reviewed product candidate may prefill, when present:

- expense amount;
- expense category suggestion;
- merchant suggestion;
- note/product summary;
- existing account seed behavior remains unchanged.

The transaction editor remains editable. User must press the normal save action before any formal transaction exists.

Unsupported category/merchant suggestions must not silently create new master data. They remain in the note or fall back to an existing safe UI default until a later canonical-candidate phase.

## 7. Safety gates

Hard requirements:

- `product candidate -> formal transaction` automatic write: FORBIDDEN
- raw Gemini API Key in UI/evidence/log: FORBIDDEN
- image retry using alternate/cropped authority without explicit contract: FORBIDDEN
- infinite Key/model retries: FORBIDDEN
- client/schema/safety errors masked by blind fallback: FORBIDDEN
- duplicate/replayed staged image silently processed as new: FORBIDDEN

## 8. Vertical slice implementation order

### P4.19.2-A — candidate + handoff contracts
- product candidate model
- structured JSON validation
- transaction seed extension
- no network yet

### P4.19.2-B — Gemini product client
- structured product prompt/schema
- exact image bytes
- no formal writes

### P4.19.2-C — resilient orchestration
- reuse Key pool/model catalog/bounded retry
- running model + elapsed status

### P4.19.2-D — ProductCapturePage integration
- staged image -> AI recognition -> candidate review
- retry/discard actions

### P4.19.2-E — transaction draft handoff
- candidate -> `TransactionEntrySeed`
- open `TransactionEntryPage`
- explicit save remains required

### P4.19.2-F — evidence + CI + signed APK
- focused product capture tests
- Full Flutter CI
- Signed Canary exact-head
- real-device camera/gallery/product recognition validation

## 9. First real-device Gate

A valid first APK must prove:

1. Home `拍照` opens `拍商品` flow.
2. Camera and gallery can create one local staged image.
3. No AI network call occurs before the user taps `AI 辨識商品`.
4. During recognition the UI displays active Gemini model + elapsed time.
5. A candidate is shown without automatically creating a transaction.
6. `帶入新增記帳` opens the normal transaction editor with candidate values prefilled.
7. Back/cancel from the transaction editor leaves no formal transaction.
8. Explicit normal save is still required to create the transaction.
