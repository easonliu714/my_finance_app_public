# Product Roadmap

This file is the forward-looking product roadmap index for `my_finance_app_public`.
Detailed acceptance criteria and implementation discussion live in linked GitHub Issues.
Completed signed/real-device authorities remain frozen and are not rewritten by roadmap work.

## Current validated baseline

### P4.19.4 — product review freshness boundary

Status: **REAL-DEVICE PASS / CLOSED FOR IMPLEMENTATION** on 2026-08-21.

Frozen authority:

- version: `4.19.4+441`
- exact source head: `cc32bcad3187e2e9c725bc9efd2b929d7bd803ff`
- signed APK SHA-256: `1ed078b173fa6c800acd81632b6014c5a3c881c5691ebeb48fb312de18044abc`
- default model for fresh/blank Gemini settings: `gemini-3.1-flash-lite`

Validated behavior includes post-confirm mutation invalidation, explicit reconfirmation before handoff, manual total override authority, full CI, signed canary and real-device gates.

## Near-term — P4.19.5 product-photo review UX

Tracking issue: **#29 — P4.19 follow-up: localized multi-item product review and calculator**

Priority: next implementation phase.

### Goals

1. Remove mixed-language production warnings from product-photo review. Internal reason codes may remain stable/English, but user-facing copy follows the current app locale.
2. Audit the Gemini product response schema for structured multi-item evidence.
3. When reliable item-level `name / quantity / unitPrice / subtotal` exists, present independently editable item rows and an aggregate total.
4. When item-level prices are not reliably associated, do **not** show one misleading aggregate `單價`; keep recognized names/quantities when available and make `總金額` the primary monetary field.
5. Add an optional manual-review calculator for subtotal, discount, coupon and arithmetic adjustments.
6. Applying a calculator result is an explicit mutation and therefore reuses the P4.19.4 freshness contract: any prior review confirmation becomes stale until reconfirmed.

### Safety boundary

- Never invent per-item unit prices from `aggregate total / aggregate quantity` for heterogeneous products.
- AI itemization remains advisory/editable.
- Explicit user paid-total override remains authoritative.
- Calculator does not silently change the amount; it requires an explicit apply action.
- No formal transaction write occurs before the existing explicit Save boundary.

## Planned — voice-assisted accounting input

Tracking issue: **#28 — Roadmap: voice-assisted natural-language accounting input**

### Goal

Add a `語音輸入` path that converts a user utterance into an editable transaction draft while preserving the same review/write safety model as other assisted input paths.

Example prompt shown in the UI:

> 我在 OK 便利商店用一卡通支付 72 元，買了 1 杯大熱拿、一個花生吐司

Expected candidate extraction when supported by existing master data:

- merchant: `OK便利商店`
- payment/account candidate: `一卡通`
- total amount: `72`
- items: `大熱拿 × 1`, `花生吐司 × 1`
- category/date/time remain reviewable and follow existing deterministic defaults/learning rules rather than being guessed.

### Preferred architecture

```text
microphone / platform speech recognizer
  → transcript
  → transcript review/correction
  → structured parse candidate
  → existing transaction draft/review boundary
  → explicit Save
  → one formal transaction
```

The transcript parser should be separable from microphone capture so it can be unit-tested with text fixtures and later reused for pasted natural-language input.

### Privacy / permission baseline

- Request microphone permission only after the user invokes voice input.
- No continuous/background listening.
- No raw-audio retention by default.
- Show transcript before formal write and allow correction.
- Permission/service/offline failure must have a text-entry fallback.
- A future network speech/LLM parser requires a separate privacy/consent contract.

## Existing roadmap dependencies

- #16 — product-photo recognition with Gemini Vision review-first accounting
- #17 — product-image crop and photo-retention settings
- #20 — merchant identity history / official business registry / local learning
- #22 — low-confidence OCR automatic Gemini fallback and compact invoice review UI

## Sequencing

1. Freeze P4.19.4 exact real-device PASS authority. **Done.**
2. P4.19.5: localized multi-item product review semantics + calculator (#29).
3. Re-run focused/full/signed/real-device gates for P4.19.5.
4. Implement voice-input vertical slice (#28): transcript-first parser + review boundary before microphone integration where practical.
5. Add microphone/platform speech recognition and real-device permission/offline gates.
6. Continue remaining roadmap items only after each phase has an explicit signed-device closure.

## Global acceptance principles

- Assisted recognition never silently creates formal transactions.
- Ambiguous fields remain blank/review-required rather than fabricated.
- User-facing copy follows the app locale.
- Existing formal merchant/category/account masters are reused; assisted flows do not silently create new master rows.
- A change after explicit review confirmation invalidates stale draft authority until reconfirmed.
- Every release candidate requires Analyze + focused tests + full CI + signed artifact inspection + real-device gates before merge/governance closure.
