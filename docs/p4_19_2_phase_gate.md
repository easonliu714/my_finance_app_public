# P4.19.2 Phase Gate

Current gate: `A_CONTRACT_GREEN / B_GEMINI_PRODUCT_CLIENT_GREEN / C_RESILIENT_PRODUCT_ORCHESTRATION_START`

## Slice A closure

Exact-head Flutter Android CI #123:

- Analyze: PASS
- Full Flutter test suite: PASS
- Debug APK build: PASS

Closed contracts:

- product candidate cannot create formal records;
- invalid/negative numeric values fail closed;
- amount derivation requires explicit quantity + unit price;
- transaction handoff remains review-only;
- no `TransactionRepository` dependency in product candidate/handoff contracts.

## Slice B closure

Exact-head Flutter Android CI #127 (`780eae4b414f8ebd375e9682a67b29f3ee844ccc`):

- Analyze: PASS
- Full Flutter test suite: PASS
- Debug APK build: PASS

Closed contracts:

- product Gemini request uses exact staged image bytes;
- structured JSON response schema only;
- unknown visual fields remain nullable;
- 401/403, 429, 5xx/timeout/network and fail-fast errors are classified separately;
- malformed/safety-blocked responses cannot trigger a formal candidate;
- API Key is header-only and never embedded in request/evidence payload;
- product client has no formal-write dependency.

## Slice C gate

Before ProductCapturePage integration:

- one explicit user action creates one logical product-recognition invocation;
- flat API Key pool rotates on quota/auth failures;
- unavailable/stale model falls back to another provider-listed Flash model;
- transient 5xx/timeout/network retries are bounded;
- request/schema/safety errors fail fast;
- staged image is loaded once and exact bytes are reused across every physical attempt;
- physical attempt cap remains bounded at 8;
- routing telemetry uses `RecognitionSessionContext` with no raw API Key;
- no product coordinator dependency on `TransactionRepository`.

Next gate after C: `D_PRODUCT_CAPTURE_PAGE_REVIEW_INTEGRATION`.
